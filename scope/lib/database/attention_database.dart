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

  /// Runs a single-step atomic transaction to clean up expired notifications,
  /// enforce storage quota caps, and purge any orphaned review queue entries.
  Future<void> runSetBasedCleanup(int cutoffTimestamp, {int? maxQuota}) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();

      // 2. Enforce max row-count storage quota cap if specified
      if (maxQuota != null && maxQuota > 0) {
        final countExpr = notificationsTable.id.count();
        final countQuery = selectOnly(notificationsTable)..addColumns([countExpr]);
        final row = await countQuery.getSingle();
        final totalCount = row.read(countExpr) ?? 0;

        if (totalCount > maxQuota) {
          final excess = totalCount - maxQuota;
          final oldestQuery = select(notificationsTable)
            ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc)])
            ..limit(excess);
          final oldestEntries = await oldestQuery.get();
          final oldestIds = oldestEntries.map((e) => e.id).toList();

          if (oldestIds.isNotEmpty) {
            await (delete(notificationsTable)..where((t) => t.id.isIn(oldestIds))).go();
          }
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
