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
    InferenceTelemetryTable,
  ],
  daos: [
    NotificationDao,
    ReviewQueueDao,
    FocusSessionDao,
    DailyBriefDao,
    UserSettingsDao,
    InferenceTelemetryDao,
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
  /// enforce storage quota / row caps, and remove orphaned review queue entries.
  Future<void> runSetBasedCleanup([
    int? cutoffTimestamp,
    int? maxQuota,
    int? storageQuotaMb,
  ]) async {
    final settings = await userSettingsDao.getUserSettings();
    final effectiveRowCap = maxQuota ?? settings.maxRowCap;

    int? effectiveCutoff = cutoffTimestamp;
    if (effectiveCutoff == null && settings.retentionDays > 0) {
      effectiveCutoff = DateTime.now()
          .subtract(Duration(days: settings.retentionDays))
          .millisecondsSinceEpoch;
    }

    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      if (effectiveCutoff != null) {
        final cutoff = effectiveCutoff;
        await (delete(notificationsTable)
              ..where((t) => t.timestamp.isSmallerThanValue(cutoff)))
            .go();

        // Also clean up telemetry logs older than cutoff
        await (delete(inferenceTelemetryTable)
              ..where((t) => t.timestamp.isSmallerThanValue(cutoff)))
            .go();
      }

      // 2. Enforce row cap limits on remaining notifications
      if (effectiveRowCap > 0) {
        final remainingNotifs = await (select(notificationsTable)
              ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc)]))
            .get();

        if (remainingNotifs.length > effectiveRowCap) {
          final excess = remainingNotifs.length - effectiveRowCap;
          final idsToDelete = remainingNotifs.take(excess).map((e) => e.id).toList();
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

  /// Calculates estimated DB storage usage in bytes.
  Future<int> getStorageUsageBytes() async {
    final notifCount = await notificationDao.getCount();
    final telemetryCount = await inferenceTelemetryDao.getTelemetryCount();
    // Estimate ~1.5KB per notification row and ~0.5KB per telemetry entry
    return (notifCount * 1536) + (telemetryCount * 512);
  }
}


QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file);
  });
}
