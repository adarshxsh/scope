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
  AttentionDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  factory AttentionDatabase.inMemory() {
    return AttentionDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appSettingsTable);
          }
        },
      );

  /// Runs a single-step atomic transaction to clean up expired notifications
  /// according to retention duration and item quota limits, and any orphaned review queue entries.
  Future<void> runSetBasedCleanup(int cutoffTimestamp, {int maxQuota = 0}) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp (if retention active)
      if (cutoffTimestamp > 0) {
        await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();
      }

      // 2. Enforce FIFO storage quota eviction if total items exceed user-specified quota
      if (maxQuota > 0) {
        final countExpr = notificationsTable.id.count();
        final countQuery = selectOnly(notificationsTable)..addColumns([countExpr]);
        final row = await countQuery.getSingle();
        final currentCount = row.read(countExpr) ?? 0;

        if (currentCount > maxQuota) {
          final excess = currentCount - maxQuota;
          final oldestSubquery = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id])
            ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc)])
            ..limit(excess);

          final oldestRows = await oldestSubquery.get();
          final idsToDelete = oldestRows.map((r) => r.read(notificationsTable.id)!).toList();

          if (idsToDelete.isNotEmpty) {
            await (delete(notificationsTable)..where((t) => t.id.isIn(idsToDelete))).go();
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
