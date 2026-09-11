import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
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
    AppSettingsTable,
  ],
  daos: [
    NotificationDao,
    ReviewQueueDao,
    FocusSessionDao,
    DailyBriefDao,
    AppSettingsDao,
  ],
)
class AttentionDatabase extends _$AttentionDatabase {
  AttentionDatabase([QueryExecutor? executor])
    : super(executor ?? _openConnection());

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  /// Runs a single-step atomic transaction to clean up expired notifications
  /// and any orphaned review queue entries, enforcing storage quotas if specified.
  Future<void> runSetBasedCleanup(int cutoffTimestamp, {int? maxCount}) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp (if cutoffTimestamp > 0)
      if (cutoffTimestamp > 0) {
        await (delete(
          notificationsTable,
        )..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();
      }

      // 2. Enforce FIFO storage quota if maxCount is specified and > 0
      if (maxCount != null && maxCount > 0) {
        await notificationDao.enforceStorageQuota(maxCount);
      }

      // 3. Delete orphaned review queue entries in a set-based query
      final orphanedQuery = delete(reviewQueueTable)
        ..where((t) {
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
