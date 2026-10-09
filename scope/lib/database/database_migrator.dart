import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// DatabaseMigrator handles detecting existing unencrypted SQLite database files
/// and performing an in-place atomic SQLCipher export migration to encrypt them.
class DatabaseMigrator {
  /// Checks if [file] exists and is unencrypted. If so, migrates it in-place
  /// to SQLCipher format encrypted with [encryptionKey].
  static Future<void> migrateUnencryptedDatabaseIfNeeded(
    File file,
    String encryptionKey,
  ) async {
    if (!file.existsSync()) {
      return;
    }

    final isUnencrypted = _isUnencryptedDatabase(file);
    if (!isUnencrypted) {
      return;
    }

    final tmpFile = File('${file.path}.tmp_encrypted');
    final bakFile = File('${file.path}.unencrypted.bak');

    if (tmpFile.existsSync()) {
      tmpFile.deleteSync();
    }
    if (bakFile.existsSync()) {
      bakFile.deleteSync();
    }

    final escapedKey = encryptionKey.replaceAll("'", "''");

    try {
      final unencryptedDb = sqlite3.open(file.path);
      try {
        final versionResult = unencryptedDb.select('PRAGMA user_version;');
        final userVersion = versionResult.first.values.first as int;

        final escapedTmpPath = tmpFile.path.replaceAll("'", "''");

        unencryptedDb.execute("ATTACH DATABASE '$escapedTmpPath' AS encrypted KEY '$escapedKey';");
        unencryptedDb.execute("SELECT sqlcipher_export('encrypted');");
        unencryptedDb.execute("PRAGMA encrypted.user_version = $userVersion;");
        unencryptedDb.execute("DETACH DATABASE encrypted;");
      } finally {
        unencryptedDb.dispose();
      }

      // Atomic swap of original database file with backup fallback
      file.renameSync(bakFile.path);
      tmpFile.renameSync(file.path);

      // Verify the migrated encrypted database opens properly with encryptionKey
      final verifyDb = sqlite3.open(file.path);
      try {
        verifyDb.execute("PRAGMA key = '$escapedKey';");
        verifyDb.select('PRAGMA user_version;');
      } catch (verifyError) {
        // Verification failed! Restore original unencrypted backup file
        if (file.existsSync()) {
          file.deleteSync();
        }
        bakFile.renameSync(file.path);
        rethrow;
      } finally {
        verifyDb.dispose();
      }

      // Migration succeeded and verified; safely remove backup file
      if (bakFile.existsSync()) {
        bakFile.deleteSync();
      }
    } catch (e) {
      if (tmpFile.existsSync()) {
        tmpFile.deleteSync();
      }
      rethrow;
    }
  }

  /// Attempts to read database metadata without a key. Returns true if readable (unencrypted).
  static bool _isUnencryptedDatabase(File file) {
    try {
      final testDb = sqlite3.open(file.path);
      try {
        testDb.select('PRAGMA user_version;');
        return true;
      } catch (_) {
        return false;
      } finally {
        testDb.dispose();
      }
    } catch (_) {
      return false;
    }
  }
}
