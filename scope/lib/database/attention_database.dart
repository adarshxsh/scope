import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';
import 'package:scope/database/database_migrator.dart';
import 'package:scope/database/secure_key_storage.dart';

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
  AttentionDatabase([QueryExecutor? executor, String? encryptionKey, File? overrideFile])
      : super(executor ?? openConnection(encryptionKey: encryptionKey, overrideFile: overrideFile));

  factory AttentionDatabase.encrypted(String key, {File? file}) {
    return AttentionDatabase(null, key, file);
  }

  factory AttentionDatabase.withKeyManager({DatabaseKeyManager? keyManager, File? file}) {
    final km = keyManager ?? DatabaseKeyManager();
    return AttentionDatabase(openConnectionWithKeyManager(km, overrideFile: file));
  }

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

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

QueryExecutor openConnectionWithKeyManager(DatabaseKeyManager keyManager, {File? overrideFile}) {
  return LazyDatabase(() async {
    final key = await keyManager.getOrCreateKey();
    final file = overrideFile ?? await getDatabaseFile();
    await _handleLegacyMigrationIfNeeded(file, key);
    return _createNativeDatabase(file, key);
  });
}

QueryExecutor openConnection({String? encryptionKey, File? overrideFile}) {
  return LazyDatabase(() async {
    final file = overrideFile ?? await getDatabaseFile();
    final key = encryptionKey ?? await DatabaseKeyManager().getOrCreateKey();
    await _handleLegacyMigrationIfNeeded(file, key);
    return _createNativeDatabase(file, key);
  });
}

Future<File> getDatabaseFile() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return File(p.join(dbFolder.path, 'attention_os.db'));
}

Future<void> _handleLegacyMigrationIfNeeded(File file, String key) async {
  if (DatabaseMigrator.isUnencryptedCleartext(file)) {
    await DatabaseMigrator.migrateCleartextToEncrypted(
      dbFile: file,
      encryptionKey: key,
    );
  }
}

QueryExecutor _createNativeDatabase(File file, String? encryptionKey) {
  return NativeDatabase(
    file,
    setup: (db) {
      if (encryptionKey != null && encryptionKey.isNotEmpty) {
        db.execute("PRAGMA key = '$encryptionKey';");
      }
    },
  );
}
