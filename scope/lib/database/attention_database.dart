import 'dart:io';
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/tables.dart';
import 'package:scope/database/daos.dart';
import 'package:scope/database/converters.dart';

part 'attention_database.g.dart';

class CleanupResult {
  final int deletedByAgeCount;
  final int deletedByRowCapCount;
  final int deletedByQuotaCount;
  final int deletedOrphanedQueueCount;
  final int freedBytes;
  final int durationMs;

  int get totalDeleted => deletedByAgeCount + deletedByRowCapCount + deletedByQuotaCount;

  const CleanupResult({
    this.deletedByAgeCount = 0,
    this.deletedByRowCapCount = 0,
    this.deletedByQuotaCount = 0,
    this.deletedOrphanedQueueCount = 0,
    this.freedBytes = 0,
    this.durationMs = 0,
  });

  @override
  String toString() {
    return 'CleanupResult(age: $deletedByAgeCount, rowCap: $deletedByRowCapCount, quota: $deletedByQuotaCount, orphanedQueue: $deletedOrphanedQueueCount, freedBytes: $freedBytes, duration: ${durationMs}ms)';
  }
}

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
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(userSettingsTable);
        }
      },
    );
  }

  /// Calculates or estimates total SQLite database storage size in bytes.
  Future<int> getStorageSizeBytes() async {
    try {
      final pageCountRow = await customSelect('PRAGMA page_count;').getSingle();
      final pageSizeRow = await customSelect('PRAGMA page_size;').getSingle();
      final pageCount = pageCountRow.read<int>('page_count');
      final pageSize = pageSizeRow.read<int>('page_size');
      return pageCount * pageSize;
    } catch (_) {
      return 0;
    }
  }

  /// Runs a single-step atomic transaction to clean up expired notifications,
  /// enforce row caps, enforce database storage quotas, and clear orphaned
  /// review queue entries.
  Future<CleanupResult> runSetBasedCleanup([
    int? cutoffTimestamp,
    int? maxNotificationRows,
    int? maxStorageQuotaBytes,
    int? storageHighWaterMarkBytes,
    bool forceEmergency = false,
  ]) async {
    final stopwatch = Stopwatch()..start();
    int ageDeleted = 0;
    int rowCapDeleted = 0;
    int quotaDeleted = 0;
    int orphanDeleted = 0;

    UserSettingsEntry? settings;
    try {
      settings = await userSettingsDao.getSettings();
    } catch (_) {
      // Handle missing settings or unit test instances
    }

    final cutoff = cutoffTimestamp ??
        DateTime.now()
            .subtract(Duration(days: settings?.retentionDays ?? 7))
            .millisecondsSinceEpoch;
    final maxRows = maxNotificationRows ?? settings?.maxNotificationRows ?? 5000;
    final maxQuota = maxStorageQuotaBytes ?? settings?.maxStorageQuotaBytes ?? (25 * 1024 * 1024);
    final highWater = storageHighWaterMarkBytes ?? settings?.storageHighWaterMarkBytes ?? (20 * 1024 * 1024);

    final initialStorageSize = await getStorageSizeBytes();

    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      ageDeleted = await (delete(notificationsTable)
            ..where((t) => t.timestamp.isSmallerThanValue(cutoff)))
          .go();

      // 2. Enforce maximum entry row limit cap
      final currentCount = await notificationDao.getCount();
      if (currentCount > maxRows) {
        final excess = currentCount - maxRows;
        final oldestSubquery = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id])
          ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc)])
          ..limit(excess);
        rowCapDeleted = await (delete(notificationsTable)
              ..where((t) => t.id.isInQuery(oldestSubquery)))
            .go();
      }

      // 3. Enforce DB Storage Quota
      int currentStorageSize = await getStorageSizeBytes();
      if (currentStorageSize > maxQuota) {
        while (currentStorageSize > highWater) {
          final countBefore = await notificationDao.getCount();
          if (countBefore == 0) break;

          final batchSize = math.min(countBefore, 100);
          final oldestBatchSubquery = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id])
            ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc)])
            ..limit(batchSize);

          final deletedInBatch = await (delete(notificationsTable)
                ..where((t) => t.id.isInQuery(oldestBatchSubquery)))
              .go();

          if (deletedInBatch == 0) break;
          quotaDeleted += deletedInBatch;

          try {
            await customStatement('PRAGMA incremental_vacuum;');
          } catch (_) {}

          currentStorageSize = await getStorageSizeBytes();
        }
      }

      // 4. Delete orphaned review queue entries in a set-based query
      final orphanedQuery = delete(reviewQueueTable)..where((t) {
        final hasNotification = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id]);
        return t.notificationId.isNotInQuery(hasNotification);
      });
      orphanDeleted = await orphanedQuery.go();

      if (ageDeleted + rowCapDeleted + quotaDeleted > 0) {
        try {
          await customStatement('PRAGMA incremental_vacuum;');
        } catch (_) {}
      }
    });

    final finalStorageSize = await getStorageSizeBytes();
    final freedBytes = math.max(0, initialStorageSize - finalStorageSize);
    stopwatch.stop();

    final result = CleanupResult(
      deletedByAgeCount: ageDeleted,
      deletedByRowCapCount: rowCapDeleted,
      deletedByQuotaCount: quotaDeleted,
      deletedOrphanedQueueCount: orphanDeleted,
      freedBytes: freedBytes,
      durationMs: stopwatch.elapsedMilliseconds,
    );

    try {
      await userSettingsDao.recordCleanup(
        count: result.totalDeleted,
        timestamp: DateTime.now(),
      );
    } catch (_) {}

    return result;
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file);
  });
}

