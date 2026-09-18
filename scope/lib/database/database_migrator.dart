import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// Handles detection and transparent inline migration of legacy unencrypted
/// SQLite database files to SQLCipher encrypted database files.
class DatabaseMigrator {
  /// Detects if [dbFile] is an unencrypted cleartext SQLite database.
  static bool isUnencryptedCleartext(File dbFile) {
    if (!dbFile.existsSync()) return false;
    try {
      final db = sqlite3.open(dbFile.path);
      try {
        final result = db.select('SELECT count(*) FROM sqlite_master;');
        return result.isNotEmpty;
      } finally {
        db.close();
      }
    } catch (_) {
      // Opening or querying failed (e.g., encrypted file throws SQLITE_NOTADB)
      return false;
    }
  }

  /// Performs inline migration from an unencrypted cleartext database to an encrypted database.
  static Future<void> migrateCleartextToEncrypted({
    required File dbFile,
    required String encryptionKey,
  }) async {
    if (!dbFile.existsSync()) return;

    final legacyPath = '${dbFile.path}.legacy';
    final legacyFile = File(legacyPath);

    if (legacyFile.existsSync()) {
      try {
        legacyFile.deleteSync();
      } catch (_) {}
    }

    // Atomically move cleartext database to legacy path
    dbFile.renameSync(legacyPath);

    final walFile = File('${dbFile.path}-wal');
    if (walFile.existsSync()) {
      try {
        walFile.renameSync('$legacyPath-wal');
      } catch (_) {}
    }

    final shmFile = File('${dbFile.path}-shm');
    if (shmFile.existsSync()) {
      try {
        shmFile.renameSync('$legacyPath-shm');
      } catch (_) {}
    }

    // Open legacy cleartext DB and create target encrypted DB
    final legacyDb = sqlite3.open(legacyFile.path);
    final encryptedDb = sqlite3.open(dbFile.path);

    try {
      encryptedDb.execute("PRAGMA key = '$encryptionKey';");

      // Extract tables and schema DDLs from legacy DB
      final tables = legacyDb.select(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'sqlite_sequence';",
      );

      for (final tableRow in tables) {
        final tableName = tableRow['name'] as String;
        final ddl = tableRow['sql'] as String?;

        if (ddl != null && ddl.isNotEmpty) {
          encryptedDb.execute(ddl);
        }

        final rows = legacyDb.select('SELECT * FROM "$tableName";');
        for (final row in rows) {
          if (row.isEmpty) continue;
          final columns = row.keys.map((c) => '"$c"').join(', ');
          final placeholders = List.filled(row.length, '?').join(', ');
          final sql = 'INSERT OR REPLACE INTO "$tableName" ($columns) VALUES ($placeholders);';
          final stmt = encryptedDb.prepare(sql);
          try {
            stmt.execute(row.values.toList());
          } finally {
            stmt.close();
          }
        }
      }
    } finally {
      legacyDb.close();
      encryptedDb.close();
    }

    // Purge legacy cleartext files immediately
    _purgeFiles([
      legacyFile,
      File('$legacyPath-wal'),
      File('$legacyPath-shm'),
    ]);
  }

  static void _purgeFiles(List<File> files) {
    for (final f in files) {
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
}
