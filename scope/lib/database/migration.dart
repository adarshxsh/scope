import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Handles automated detection and atomic migration of unencrypted SQLite databases
/// to encrypted SQLCipher databases.
class DatabaseMigrator {
  /// Checks whether SQLCipher encryption is supported by the loaded SQLite library.
  static bool isSqlCipherSupported() {
    try {
      final db = sqlite3.sqlite3.openInMemory();
      final result = db.select('PRAGMA cipher_version;');
      db.close();
      return result.isNotEmpty && result.first.values.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether [dbFile] is an unencrypted (plaintext) SQLite database.
  static bool isPlaintextDatabase(File dbFile) {
    if (!dbFile.existsSync() || dbFile.lengthSync() == 0) {
      return false;
    }

    if (!isSqlCipherSupported()) {
      return true;
    }

    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(dbFile.path);
      db.select('SELECT count(*) FROM sqlite_master;');
      db.close();
      return true;
    } catch (_) {
      try {
        db?.close();
      } catch (_) {}
      return false;
    }
  }

  /// Checks whether [dbFile] can be successfully read when opened with [passphrase].
  static bool isEncryptedWithKey(File dbFile, String passphrase) {
    if (!dbFile.existsSync() || dbFile.lengthSync() == 0) {
      return false;
    }
    sqlite3.Database? db;
    try {
      db = sqlite3.sqlite3.open(dbFile.path);
      final escapedKey = passphrase.replaceAll("'", "''");
      db.execute("PRAGMA key = '$escapedKey';");
      db.select('SELECT count(*) FROM sqlite_master;');
      db.close();
      return true;
    } catch (_) {
      try {
        db?.close();
      } catch (_) {}
      return false;
    }
  }

  /// Migrates an unencrypted SQLite database file [dbFile] into an encrypted
  /// SQLCipher database using [passphrase].
  /// Returns `true` if migration was performed, or `false` if no migration was necessary.
  static Future<bool> migrateIfNeeded(File dbFile, String passphrase) async {
    if (!dbFile.existsSync() || dbFile.lengthSync() == 0) {
      return false;
    }

    // 1. If SQLCipher is active and file is already encrypted with key, skip
    if (isSqlCipherSupported() && isEncryptedWithKey(dbFile, passphrase) && !isPlaintextDatabase(dbFile)) {
      return false;
    }

    // 2. Prepare temporary and backup target files
    final tempEncryptedFile = File('${dbFile.path}.tmp_encrypted');
    if (tempEncryptedFile.existsSync()) {
      tempEncryptedFile.deleteSync();
    }

    final backupFile = File('${dbFile.path}.plaintext_bak');
    if (backupFile.existsSync()) {
      backupFile.deleteSync();
    }

    bool success = false;
    try {
      // Attempt SQLCipher native export first
      success = _trySqlCipherExport(dbFile, tempEncryptedFile, passphrase);

      if (!success) {
        // Fall back to schema and data copy
        success = _fallbackSchemaAndDataCopy(dbFile, tempEncryptedFile, passphrase);
      }

      if (!success) {
        throw Exception('Failed to convert plaintext database to encrypted format.');
      }

      // Verify integrity if SQLCipher is supported
      if (isSqlCipherSupported() && !isEncryptedWithKey(tempEncryptedFile, passphrase)) {
        throw Exception('Migration integrity check failed: Encrypted database cannot be accessed with passphrase.');
      }

      // Perform atomic file swap
      dbFile.renameSync(backupFile.path);
      tempEncryptedFile.renameSync(dbFile.path);

      if (backupFile.existsSync()) {
        backupFile.deleteSync();
      }
      return true;
    } catch (e) {
      // Rollback on failure
      if (tempEncryptedFile.existsSync()) {
        try {
          tempEncryptedFile.deleteSync();
        } catch (_) {}
      }
      if (!dbFile.existsSync() && backupFile.existsSync()) {
        try {
          backupFile.renameSync(dbFile.path);
        } catch (_) {}
      }
      rethrow;
    }
  }

  static bool _trySqlCipherExport(File sourceFile, File targetFile, String passphrase) {
    sqlite3.Database? sourceDb;
    try {
      sourceDb = sqlite3.sqlite3.open(sourceFile.path);
      final escapedKey = passphrase.replaceAll("'", "''");
      final escapedTargetPath = targetFile.path.replaceAll("'", "''");

      sourceDb.execute("ATTACH DATABASE '$escapedTargetPath' AS encrypted KEY '$escapedKey';");
      sourceDb.execute("SELECT sqlcipher_export('encrypted');");
      sourceDb.execute("DETACH DATABASE encrypted;");
      sourceDb.close();
      return true;
    } catch (_) {
      try {
        sourceDb?.close();
      } catch (_) {}
      return false;
    }
  }

  static bool _fallbackSchemaAndDataCopy(File sourceFile, File targetFile, String passphrase) {
    sqlite3.Database? sourceDb;
    sqlite3.Database? targetDb;
    try {
      sourceDb = sqlite3.sqlite3.open(sourceFile.path);
      targetDb = sqlite3.sqlite3.open(targetFile.path);

      final escapedKey = passphrase.replaceAll("'", "''");
      targetDb.execute("PRAGMA key = '$escapedKey';");
      targetDb.execute("PRAGMA foreign_keys = OFF;");

      final tables = sourceDb.select(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );

      for (final row in tables) {
        final tableName = row['name'] as String;
        final createSql = row['sql'] as String?;
        if (createSql != null) {
          targetDb.execute(createSql);

          final rows = sourceDb.select('SELECT * FROM "$tableName";');
          if (rows.isNotEmpty) {
            final columns = rows.first.keys.toList();
            final colList = columns.map((c) => '"$c"').join(', ');
            final placeholders = List.filled(columns.length, '?').join(', ');

            final insertStmt = targetDb.prepare('INSERT INTO "$tableName" ($colList) VALUES ($placeholders);');
            try {
              for (final r in rows) {
                insertStmt.execute(r.values);
              }
            } finally {
              insertStmt.close();
            }
          }
        }
      }

      final indices = sourceDb.select(
        "SELECT sql FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' AND sql IS NOT NULL;",
      );
      for (final row in indices) {
        final indexSql = row['sql'] as String?;
        if (indexSql != null) {
          targetDb.execute(indexSql);
        }
      }

      sourceDb.close();
      targetDb.close();
      return true;
    } catch (_) {
      try {
        sourceDb?.close();
      } catch (_) {}
      try {
        targetDb?.close();
      } catch (_) {}
      return false;
    }
  }
}
