import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// Helper functions for SQLCipher database encryption and re-encrypting existing database files.
class DatabaseEncryptionHelper {
  /// Checks if [dbFile] exists and is unencrypted SQLite.
  /// If unencrypted, re-encrypts the entire database file using SQLCipher with [passphrase].
  static Future<void> ensureDatabaseEncrypted(File dbFile, String passphrase) async {
    if (!dbFile.existsSync() || dbFile.lengthSync() == 0) {
      return;
    }

    // Read the 16-byte header to check if the file is unencrypted SQLite
    final bytes = await dbFile.openRead(0, 16).first;
    if (bytes.length < 16) {
      return;
    }

    final header = String.fromCharCodes(bytes.sublist(0, 16));
    final isUnencrypted = header == 'SQLite format 3\x00';

    if (!isUnencrypted) {
      // File is already encrypted with SQLCipher
      return;
    }

    final tmpFilePath = '${dbFile.path}.tmp';
    final tmpFile = File(tmpFilePath);
    if (tmpFile.existsSync()) {
      tmpFile.deleteSync();
    }

    // Open unencrypted SQLite database
    final db = sqlite3.open(dbFile.path);
    try {
      db.execute("ATTACH DATABASE '$tmpFilePath' AS encrypted KEY '$passphrase';");
      try {
        db.execute("SELECT sqlcipher_export('encrypted');");
      } catch (_) {
        _exportTablesFallback(db);
      }
      db.execute("DETACH DATABASE encrypted;");
    } finally {
      db.close();
    }

    // Replace original unencrypted database file with the newly encrypted database file
    if (tmpFile.existsSync()) {
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }
      tmpFile.renameSync(dbFile.path);
    }
  }

  static void _exportTablesFallback(Database db) {
    final tables = db.select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';");
    for (final row in tables) {
      final tableName = row['name'] as String;
      db.execute('CREATE TABLE encrypted."$tableName" AS SELECT * FROM main."$tableName" WHERE 0;');
      db.execute('INSERT INTO encrypted."$tableName" SELECT * FROM main."$tableName";');
    }

    final indexes = db.select("SELECT sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL;");
    for (final row in indexes) {
      final indexSql = row['sql'] as String?;
      if (indexSql != null) {
        db.execute(indexSql);
      }
    }
  }

  /// Checks if SQLCipher extension is active in the current sqlite3 database.
  static bool isSqlCipherSupported(Database db) {
    try {
      final result = db.select('PRAGMA cipher_version;');
      return result.isNotEmpty && result.first.values.isNotEmpty && result.first.values.first != null;
    } catch (_) {
      return false;
    }
  }
}
