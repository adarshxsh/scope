import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/storage_logger.dart';
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

  static const int maxStorageQuota = 500;

  @override
  int get schemaVersion => 1;

  /// Enforces maximum entry row limit (max 500 notifications) using an atomic
  /// SQLite transaction. Evicts the oldest notifications exceeding the quota.
  Future<int> enforceCapacityLimit({int maxItems = maxStorageQuota}) async {
    int evictedCount = 0;
    try {
      await transaction(() async {
        final totalCount = await notificationDao.getCount();
        if (totalCount > maxItems) {
          final excess = totalCount - maxItems;

          final oldestEntries = await (select(notificationsTable)
                ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc)])
                ..limit(excess))
              .get();
          final oldestIds = oldestEntries.map((e) => e.id).toList();

          if (oldestIds.isNotEmpty) {
            await (delete(reviewQueueTable)..where((t) => t.notificationId.isIn(oldestIds))).go();
            evictedCount = await (delete(notificationsTable)..where((t) => t.id.isIn(oldestIds))).go();
          }
        }

        final orphanedQuery = delete(reviewQueueTable)..where((t) {
          final hasNotification = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id]);
          return t.notificationId.isNotInQuery(hasNotification);
        });
        await orphanedQuery.go();
      });

      if (evictedCount > 0) {
        StorageLogger.logCapacityEnforced(
          currentCount: await notificationDao.getCount(),
          maxCapacity: maxItems,
          evictedCount: evictedCount,
        );
      }
    } catch (e, st) {
      StorageLogger.logStorageError('enforceCapacityLimit', e, st);
    }
    return evictedCount;
  }

  /// Runs a single-step atomic transaction to clean up expired notifications,
  /// enforce capacity limits, and clear orphaned review queue entries.
  Future<void> runSetBasedCleanup(int cutoffTimestamp, {int maxItems = maxStorageQuota}) async {
    final stopwatch = Stopwatch()..start();
    int deletedExpired = 0;
    int evictedCapacity = 0;

    try {
      await transaction(() async {
        // 1. Delete expired notifications based on cutoff timestamp
        deletedExpired = await (delete(notificationsTable)
              ..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp)))
            .go();

        // 2. Enforce capacity quota
        final totalCount = await notificationDao.getCount();
        if (totalCount > maxItems) {
          final excess = totalCount - maxItems;
          final oldestEntries = await (select(notificationsTable)
                ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc)])
                ..limit(excess))
              .get();
          final oldestIds = oldestEntries.map((e) => e.id).toList();

          if (oldestIds.isNotEmpty) {
            await (delete(reviewQueueTable)..where((t) => t.notificationId.isIn(oldestIds))).go();
            evictedCapacity = await (delete(notificationsTable)..where((t) => t.id.isIn(oldestIds))).go();
          }
        }

        // 3. Delete orphaned review queue entries
        final orphanedQuery = delete(reviewQueueTable)..where((t) {
          final hasNotification = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id]);
          return t.notificationId.isNotInQuery(hasNotification);
        });
        await orphanedQuery.go();
      });

      stopwatch.stop();
      final remaining = await notificationDao.getCount();
      StorageLogger.logStorageCleanup(
        deletedCount: deletedExpired,
        evictedCount: evictedCapacity,
        durationMs: stopwatch.elapsedMilliseconds,
        totalRemaining: remaining,
      );
    } catch (e, st) {
      StorageLogger.logStorageError('runSetBasedCleanup', e, st);
    }
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file, setup: (db) {
      db.execute('PRAGMA journal_mode = WAL;');
      db.execute('PRAGMA synchronous = NORMAL;');
      db.execute('PRAGMA foreign_keys = ON;');
    });
  });
}
