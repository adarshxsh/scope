import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/secure_key_storage.dart';
import 'package:scope/database/database_cipher.dart';

part 'attention_database.g.dart';

@DriftDatabase(
  tables: [
    NotificationsTable,
    ReviewQueueTable,
    FocusSessionsTable,
    DailyBriefTable,
  ],
  daos: [
    NotificationDao,
    ReviewQueueDao,
    FocusSessionDao,
    DailyBriefDao,
  ],
)
class AttentionDatabase extends _$AttentionDatabase {
  AttentionDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  factory AttentionDatabase.encrypted(String passphrase) {
    return AttentionDatabase(_openConnection(passphrase));
  }

  @override
  int get schemaVersion => 1;

  /// Migrates a pre-existing unencrypted database file to an encrypted SQLCipher database file in place.
  static void migrateUnencryptedIfNeeded(File file, String passphrase) {
    if (!file.existsSync()) return;
    final length = file.lengthSync();
    if (length < 16) return;

    final handle = file.openSync(mode: FileMode.read);
    final headerBytes = handle.readSync(16);
    handle.closeSync();

    final headerString = String.fromCharCodes(headerBytes);
    if (!headerString.startsWith('SQLite format 3')) {
      // File is already encrypted or not a plaintext SQLite database
      return;
    }

    final dbFolder = file.parent.path;
    final tempPath = p.join(dbFolder, 'attention_os_migrating.db');
    final tempFile = File(tempPath);
    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    bool migratedWithSqlCipher = false;
    try {
      final rawDb = sqlite3.open(file.path);
      try {
        rawDb.execute("ATTACH DATABASE '$tempPath' AS encrypted KEY '$passphrase';");
        rawDb.execute("SELECT sqlcipher_export('encrypted');");
        rawDb.execute("DETACH DATABASE encrypted;");
        rawDb.dispose();

        if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
          final tempHeader = tempFile.openSync(mode: FileMode.read).readSync(16);
          if (!String.fromCharCodes(tempHeader).startsWith('SQLite format 3')) {
            migratedWithSqlCipher = true;
            file.deleteSync();
            tempFile.renameSync(file.path);
          }
        }
      } catch (_) {
        rawDb.dispose();
      }
    } catch (_) {}

    if (tempFile.existsSync()) {
      tempFile.deleteSync();
    }

    if (!migratedWithSqlCipher) {
      final plainBytes = file.readAsBytesSync();
      final encryptedBytes = DatabaseCipher.encrypt(plainBytes, passphrase);
      file.writeAsBytesSync(encryptedBytes);
    }
  }

  /// Runs a single-step atomic transaction to clean up expired notifications
  /// and any orphaned review queue entries, avoiding main-thread loops.
  Future<void> runSetBasedCleanup(int cutoffTimestamp) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();

      // 2. Delete orphaned review queue entries in a set-based query
      final orphanedQuery = delete(reviewQueueTable)..where((t) {
        final hasNotification = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id]);
        return t.notificationId.isNotInQuery(hasNotification);
      });
      await orphanedQuery.go();
    });
  }
}

QueryExecutor _openConnection([String? passphrase]) {
  return LazyDatabase(() async {
    final key = passphrase ?? await SecureKeyStorage().getOrCreatePassphrase();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));

    if (file.existsSync()) {
      AttentionDatabase.migrateUnencryptedIfNeeded(file, key);
    }

    if (file.existsSync() && DatabaseCipher.isEncrypted(file)) {
      final encryptedBytes = file.readAsBytesSync();
      final decryptedBytes = DatabaseCipher.decrypt(encryptedBytes, key);
      final tempFile = File(p.join(dbFolder.path, 'attention_os_unlocked.db'));
      tempFile.writeAsBytesSync(decryptedBytes);

      return NativeDatabase(tempFile);
    }

    return NativeDatabase(
      file,
      setup: (db) {
        if (key.isNotEmpty) {
          db.execute("PRAGMA key = '$key';");
        }
      },
    );
  });
}
