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
    UserSettingsTable,
  ],
  daos: [
    NotificationDao,
    ReviewQueueDao,
    FocusSessionDao,
    DailyBriefDao,
    UserSettingsDao,
  ],
)
class AttentionDatabase extends _$AttentionDatabase {
  AttentionDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  /// Runs a single-step atomic transaction to clean up expired notifications based on timestamp cutoff,
  /// enforce max notification storage quota, and delete any orphaned review queue entries.
  Future<void> runSetBasedCleanup(int cutoffTimestamp, {int? storageQuotaLimit}) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp (if cutoffTimestamp > 0)
      if (cutoffTimestamp > 0) {
        await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();
      }

      // 2. Enforce maximum storage quota cap by pruning oldest active/archived notifications
      if (storageQuotaLimit != null && storageQuotaLimit > 0) {
        final countExpr = notificationsTable.id.count();
        final countQuery = selectOnly(notificationsTable)..addColumns([countExpr]);
        final countRow = await countQuery.getSingle();
        final totalCount = countRow.read(countExpr) ?? 0;

        if (totalCount > storageQuotaLimit) {
          final excess = totalCount - storageQuotaLimit;
          final oldestIdsQuery = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id])
            ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc)])
            ..limit(excess);
          await (delete(notificationsTable)..where((t) => t.id.isInQuery(oldestIdsQuery))).go();
        }
      }

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
