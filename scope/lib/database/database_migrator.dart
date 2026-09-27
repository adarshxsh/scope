import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Handles migrating legacy unencrypted SQLite databases to SQLCipher encrypted databases.
class DatabaseMigrator {
  /// Standard 16-byte SQLite header signature: "SQLite format 3\x00"
  static const List<int> sqliteHeader = [
    83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0
  ];

  /// Checks if the file at [dbFile] is an unencrypted SQLite database and migrates it to
  /// an encrypted SQLCipher database using [passphrase].
  static Future<bool> migrateUnencryptedIfNeeded(File dbFile, String passphrase) async {
    if (!dbFile.existsSync() || dbFile.lengthSync() == 0) {
      return false;
    }

    // Read initial 16 bytes to check SQLite header
    final bytes = await dbFile.openRead(0, 16).first;
    if (bytes.length < 16) {
      return false;
    }

    final isUnencrypted = listEquals(bytes.sublist(0, 16), sqliteHeader);
    if (!isUnencrypted) {
      return false; // File is already encrypted or not a standard SQLite file
    }

    final tempFile = File('${dbFile.path}.encrypted_tmp');
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    final rawDb = sqlite3.sqlite3.open(dbFile.path);
    try {
      // Flush Write-Ahead Log into main database file prior to export
      try {
        rawDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      } catch (_) {}

      // Attach new encrypted database
      final escapedTempPath = tempFile.path.replaceAll("'", "''");
      final escapedPassphrase = passphrase.replaceAll("'", "''");
      rawDb.execute("ATTACH DATABASE '$escapedTempPath' AS encrypted KEY '$escapedPassphrase';");

      try {
        rawDb.execute("SELECT sqlcipher_export('encrypted');");
      } catch (_) {
        // sqlcipher_export extension function not present on source handle, fallback to manual schema/data copy
        _fallbackExportToEncrypted(rawDb);
      }

      rawDb.execute('DETACH DATABASE encrypted;');
      rawDb.dispose();

      // Clean up WAL/SHM sidecars for old unencrypted database
      final walFile = File('${dbFile.path}-wal');
      if (walFile.existsSync()) walFile.deleteSync();
      final shmFile = File('${dbFile.path}-shm');
      if (shmFile.existsSync()) shmFile.deleteSync();

      // Replace old unencrypted database file with newly encrypted database file
      if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
        tempFile.copySync(dbFile.path);
        tempFile.deleteSync();
        return true;
      }
    } catch (e) {
      try { rawDb.dispose(); } catch (_) {}
      if (tempFile.existsSync()) {
        try { tempFile.deleteSync(); } catch (_) {}
      }
      rethrow;
    }
    return false;
  }

  static void _fallbackExportToEncrypted(sqlite3.Database rawDb) {
    // 1. Copy table structures and records
    final tables = rawDb.select(
      "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
    );

    for (final row in tables) {
      final name = row['name'] as String;
      final sql = row['sql'] as String?;
      if (sql != null && sql.isNotEmpty) {
        final createEncryptedTableSql = sql.replaceFirst(
          RegExp(r'CREATE TABLE\s+"?', caseSensitive: false),
          'CREATE TABLE encrypted.',
        );
        rawDb.execute(createEncryptedTableSql);
        rawDb.execute('INSERT INTO encrypted."$name" SELECT * FROM "$name";');
      }
    }

    // 2. Copy indexes
    final indexes = rawDb.select(
      "SELECT sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%';",
    );

    for (final row in indexes) {
      final sql = row['sql'] as String?;
      if (sql != null && sql.isNotEmpty) {
        final createEncryptedIndexSql = sql.replaceFirst(
          RegExp(r'CREATE INDEX\s+"?', caseSensitive: false),
          'CREATE INDEX encrypted.',
        );
        try {
          rawDb.execute(createEncryptedIndexSql);
        } catch (_) {}
      }
    }
  }
}
