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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(userSettingsTable);
          }
        },
      );

  /// Runs a single-step atomic transaction to clean up expired notifications,
  /// enforce row cap and MB storage quotas, and clear orphaned review queue entries.
  Future<void> runSetBasedCleanup(
    int cutoffTimestamp, {
    int? maxRowCap,
    int? maxStorageMb,
    bool clearTelemetry = false,
  }) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp (if cutoff > 0)
      if (cutoffTimestamp > 0) {
        await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();
      }

      // 2. Enforce row cap if maxRowCap is set and > 0
      if (maxRowCap != null && maxRowCap > 0) {
        final totalCount = await notificationDao.getCount();
        if (totalCount > maxRowCap) {
          final excess = totalCount - maxRowCap;
          final oldestIdsSubquery = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id])
            ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc)])
            ..limit(excess);
          await (delete(notificationsTable)..where((t) => t.id.isInQuery(oldestIdsSubquery))).go();
        }
      }

      // 3. Enforce MB storage quota if maxStorageMb is set and > 0
      if (maxStorageMb != null && maxStorageMb > 0) {
        final currentCount = await notificationDao.getCount();
        final targetMaxRows = (maxStorageMb * 1024 * 1024) ~/ 1500;
        if (currentCount > targetMaxRows && targetMaxRows > 0) {
          final excessRows = currentCount - targetMaxRows;
          final oldestQuotaSubquery = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id])
            ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc)])
            ..limit(excessRows);
          await (delete(notificationsTable)..where((t) => t.id.isInQuery(oldestQuotaSubquery))).go();
        }
      }

      // 4. Optionally clear telemetry logs if telemetry is disabled
      if (clearTelemetry) {
        await dailyBriefDao.clearAll();
      }

      // 5. Delete orphaned review queue entries in a set-based query
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
