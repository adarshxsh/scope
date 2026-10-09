import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// Utility class for detecting legacy unencrypted SQLite databases
/// and executing an in-place migration to SQLCipher encrypted format.
class DatabaseMigrator {
  /// Detects if the specified database file is an unencrypted legacy SQLite database.
  static bool isUnencryptedDatabase(File file) {
    if (!file.existsSync() || file.lengthSync() == 0) {
      return false;
    }

    try {
      final raf = file.openSync(mode: FileMode.read);
      final bytes = raf.readSync(16);
      raf.closeSync();

      final header = String.fromCharCodes(bytes);
      if (!header.startsWith('SQLite format 3')) {
        return false;
      }
    } catch (_) {
      return false;
    }

    try {
      final rawDb = sqlite3.open(file.path);
      try {
        rawDb.select('SELECT count(*) FROM sqlite_master;');
        return true;
      } finally {
        rawDb.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Automatically migrates an unencrypted database file to an encrypted SQLCipher format.
  static Future<void> migrateIfUnencrypted(File file, String encryptionKey) async {
    if (!isUnencryptedDatabase(file)) {
      return;
    }

    final tempEncryptedFile = File('${file.path}.tmp_encrypted');
    if (tempEncryptedFile.existsSync()) {
      tempEncryptedFile.deleteSync();
    }

    try {
      final rawDb = sqlite3.open(file.path);
      try {
        rawDb.execute("ATTACH DATABASE '${tempEncryptedFile.path}' AS encrypted KEY '$encryptionKey';");
        rawDb.execute("SELECT sqlcipher_export('encrypted');");
        rawDb.execute("DETACH DATABASE encrypted;");
      } finally {
        rawDb.close();
      }

      if (tempEncryptedFile.existsSync() && tempEncryptedFile.lengthSync() > 0) {
        file.deleteSync();
        tempEncryptedFile.renameSync(file.path);

        // Remove stale unencrypted journal and WAL files
        final walFile = File('${file.path}-wal');
        if (walFile.existsSync()) walFile.deleteSync();
        final shmFile = File('${file.path}-shm');
        if (shmFile.existsSync()) shmFile.deleteSync();
        final journalFile = File('${file.path}-journal');
        if (journalFile.existsSync()) journalFile.deleteSync();
      }
    } on SqliteException catch (e) {
      if (tempEncryptedFile.existsSync()) {
        try {
          tempEncryptedFile.deleteSync();
        } catch (_) {}
      }
      if (e.message.contains('no such function: sqlcipher_export')) {
        return;
      }
      rethrow;
    } catch (_) {
      // Clean up temporary file if migration failed
      if (tempEncryptedFile.existsSync()) {
        try {
          tempEncryptedFile.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }
}
