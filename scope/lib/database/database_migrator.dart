import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// Handles detection and atomic migration of legacy plaintext SQLite databases
/// to encrypted SQLCipher databases.
class DatabaseMigrator {
  static const List<int> _sqliteHeaderBytes = [
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
  ];

  /// Returns true if the file exists and has the standard cleartext SQLite header ("SQLite format 3\0").
  static Future<bool> isPlaintextSqlite(File file) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length < 16) return false;
    final handle = await file.open(mode: FileMode.read);
    final header = await handle.read(16);
    await handle.close();
    if (header.length < 16) return false;
    for (int i = 0; i < 16; i++) {
      if (header[i] != _sqliteHeaderBytes[i]) return false;
    }
    return true;
  }

  /// Atomically migrates a legacy unencrypted SQLite database file to an encrypted SQLCipher file.
  /// Preserves 100% of rows across all tables.
  static Future<void> migratePlaintextToEncrypted({
    required File targetDbFile,
    required String passphrase,
  }) async {
    if (!await isPlaintextSqlite(targetDbFile)) {
      return;
    }

    final parentDir = targetDbFile.parent.path;
    final legacyFile = File('$parentDir/attention_os_legacy.db');

    // If a leftover legacy file exists, delete it before renaming
    if (await legacyFile.exists()) {
      await legacyFile.delete();
    }

    // Rename current plaintext file to legacy file
    await targetDbFile.rename(legacyFile.path);

    Database? legacyDb;
    Database? encryptedDb;

    try {
      // 1. Open legacy database without encryption
      legacyDb = sqlite3.open(legacyFile.path);

      // 2. Open new target database and set encryption passphrase
      encryptedDb = sqlite3.open(targetDbFile.path);
      encryptedDb.execute("PRAGMA key = '$passphrase';");

      // 3. Recreate table schemas in encrypted database
      final tableSchemas = legacyDb.select(
        "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );

      for (final tableRow in tableSchemas) {
        final createSql = tableRow['sql'] as String?;
        if (createSql != null && createSql.isNotEmpty) {
          encryptedDb.execute(createSql);
        }
      }

      // Recreate index schemas
      final indexSchemas = legacyDb.select(
        "SELECT sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%';",
      );
      for (final indexRow in indexSchemas) {
        final createSql = indexRow['sql'] as String?;
        if (createSql != null && createSql.isNotEmpty) {
          encryptedDb.execute(createSql);
        }
      }

      // 4. Migrate data across all tables inside a single atomic transaction
      encryptedDb.execute('BEGIN TRANSACTION;');

      final tableNames = tableSchemas.map((r) => r['name'] as String).toList();
      final rowCountsLegacy = <String, int>{};

      for (final tableName in tableNames) {
        final countRes = legacyDb.select('SELECT count(*) as cnt FROM "$tableName";');
        final legacyCount = countRes.first['cnt'] as int;
        rowCountsLegacy[tableName] = legacyCount;

        final rows = legacyDb.select('SELECT * FROM "$tableName";');
        if (rows.isNotEmpty) {
          final columns = rows.first.keys;
          final placeholders = List.filled(columns.length, '?').join(', ');
          final colNames = columns.map((c) => '"$c"').join(', ');
          final insertSql = 'INSERT INTO "$tableName" ($colNames) VALUES ($placeholders);';

          final stmt = encryptedDb.prepare(insertSql);
          for (final row in rows) {
            stmt.execute(row.values);
          }
          stmt.dispose();
        }
      }

      encryptedDb.execute('COMMIT;');

      // 5. Verify 100% row preservation
      for (final tableName in tableNames) {
        final encCountRes = encryptedDb.select('SELECT count(*) as cnt FROM "$tableName";');
        final encCount = encCountRes.first['cnt'] as int;
        final legacyCount = rowCountsLegacy[tableName] ?? 0;

        if (encCount != legacyCount) {
          throw StateError(
            'Migration row mismatch for table $tableName: expected $legacyCount, got $encCount',
          );
        }
      }

      // Close handles
      legacyDb.dispose();
      legacyDb = null;
      encryptedDb.dispose();
      encryptedDb = null;

      // 6. Delete legacy unencrypted database file
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    } catch (e) {
      // Clean up handles on error
      try {
        legacyDb?.dispose();
      } catch (_) {}
      try {
        encryptedDb?.dispose();
      } catch (_) {}

      // Rollback file state: remove failed target file and restore legacy file
      if (await targetDbFile.exists()) {
        await targetDbFile.delete();
      }
      if (await legacyFile.exists()) {
        await legacyFile.rename(targetDbFile.path);
      }
      rethrow;
    }
  }
}
