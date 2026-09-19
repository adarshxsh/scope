import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';

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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS cap_notifications_after_insert
        AFTER INSERT ON notifications_table
        BEGIN
          DELETE FROM notifications_table WHERE id IN (
            SELECT id FROM notifications_table ORDER BY timestamp DESC, created_at DESC LIMIT -1 OFFSET 500
          );
          DELETE FROM review_queue_table WHERE notification_id NOT IN (
            SELECT id FROM notifications_table
          );
        END;
      ''');
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS cap_notifications_after_update
        AFTER UPDATE ON notifications_table
        BEGIN
          DELETE FROM notifications_table WHERE id IN (
            SELECT id FROM notifications_table ORDER BY timestamp DESC, created_at DESC LIMIT -1 OFFSET 500
          );
          DELETE FROM review_queue_table WHERE notification_id NOT IN (
            SELECT id FROM notifications_table
          );
        END;
      ''');
    },
  );

  /// Runs a single-step atomic transaction to clean up expired notifications,
  /// enforce FIFO row limits, and clean up any orphaned review queue entries,
  /// avoiding main-thread loops.
  Future<void> runSetBasedCleanup(
    int cutoffTimestamp, {
    int maxRows = NotificationStorage.defaultMaxRows,
  }) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();

      // 2. Enforce FIFO row count boundary
      await notificationDao.enforceMaxRows(maxRows);

      // 3. Delete orphaned review queue entries in a set-based query
      final orphanedQuery = delete(reviewQueueTable)..where((t) {
        final hasNotification = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id]);
        return t.notificationId.isNotInQuery(hasNotification);
      });
      await orphanedQuery.go();
    });
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file);
  });
}
