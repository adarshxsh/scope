import 'dart:io';
import 'package:flutter/foundation.dart';
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
    return AttentionDatabase(NativeDatabase.memory(setup: (rawDb) {
      try {
        rawDb.execute('PRAGMA auto_vacuum = INCREMENTAL;');
        rawDb.execute('PRAGMA journal_mode = WAL;');
      } catch (_) {}
    }));
  }

  @override
  int get schemaVersion => 1;

  /// Runs an atomic set-based transaction to enforce database retention cutoffs,
  /// row caps (max 5,000 rows), byte storage quotas (25 MB ceiling / 20 MB target),
  /// orphaned review queue cleanup, and incremental vacuuming.
  Future<void> runSetBasedCleanup(
    int cutoffTimestamp, {
    int maxRows = 5000,
    int maxFileSizeBytes = 25 * 1024 * 1024, // 25 MB ceiling
    int targetFileSizeBytes = 20 * 1024 * 1024, // 20 MB high-water mark
  }) async {
    _logStructured('START', 'Starting set-based cleanup', {
      'cutoffTimestamp': cutoffTimestamp,
      'maxRows': maxRows,
      'maxFileSizeBytes': maxFileSizeBytes,
      'targetFileSizeBytes': targetFileSizeBytes,
    });

    try {
      int initialCount = 0;
      int deletedByAge = 0;
      int deletedByCap = 0;
      int deletedByQuota = 0;
      int deletedOrphans = 0;

      await transaction(() async {
        final countExpr = notificationsTable.id.count();
        final initialCountRow = await (selectOnly(notificationsTable)..addColumns([countExpr])).getSingle();
        initialCount = initialCountRow.read(countExpr) ?? 0;

        // 1. Delete expired notifications older than cutoffTimestamp
        deletedByAge = await (delete(notificationsTable)
              ..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp)))
            .go();

        // 2. Enforce row cap (keep at most maxRows newest notifications)
        final countAfterAgeRow = await (selectOnly(notificationsTable)..addColumns([countExpr])).getSingle();
        final countAfterAge = countAfterAgeRow.read(countExpr) ?? 0;

        if (countAfterAge > maxRows) {
          final keepQuery = selectOnly(notificationsTable)
            ..addColumns([notificationsTable.id])
            ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.desc)])
            ..limit(maxRows);

          deletedByCap = await (delete(notificationsTable)
                ..where((t) => t.id.isNotInQuery(keepQuery)))
              .go();
        }

        // 3. Enforce byte quota / database file size threshold
        final currentSizeBytes = await _getDatabaseSizeBytes();
        if (currentSizeBytes > maxFileSizeBytes) {
          final countRow = await (selectOnly(notificationsTable)..addColumns([countExpr])).getSingle();
          final currentCount = countRow.read(countExpr) ?? 0;

          if (currentCount > 0) {
            final ratio = targetFileSizeBytes / currentSizeBytes;
            final targetRows = (currentCount * ratio).floor().clamp(1, currentCount);

            if (targetRows < currentCount) {
              final keepQuery = selectOnly(notificationsTable)
                ..addColumns([notificationsTable.id])
                ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.desc)])
                ..limit(targetRows);

              deletedByQuota = await (delete(notificationsTable)
                    ..where((t) => t.id.isNotInQuery(keepQuery)))
                  .go();
            }
          }
        }

        // 4. Delete orphaned review queue entries
        final keepNotificationIds = selectOnly(notificationsTable)..addColumns([notificationsTable.id]);
        final orphanedQuery = delete(reviewQueueTable)
          ..where((t) => t.notificationId.isNotInQuery(keepNotificationIds));
        deletedOrphans = await orphanedQuery.go();
      });

      // 5. Execute incremental vacuum (or standard vacuum) outside transaction to reclaim space
      try {
        await customStatement('PRAGMA incremental_vacuum;');
      } catch (vErr) {
        _logStructured('WARN', 'Incremental vacuum failed, attempting fallback vacuum', {'error': vErr.toString()});
        try {
          await customStatement('VACUUM;');
        } catch (_) {}
      }

      final finalSizeBytes = await _getDatabaseSizeBytes();
      final countExpr = notificationsTable.id.count();
      final finalCountRow = await (selectOnly(notificationsTable)..addColumns([countExpr])).getSingle();
      final finalCount = finalCountRow.read(countExpr) ?? 0;

      _logStructured('COMPLETE', 'Set-based cleanup finished successfully', {
        'initialCount': initialCount,
        'finalCount': finalCount,
        'deletedByAge': deletedByAge,
        'deletedByCap': deletedByCap,
        'deletedByQuota': deletedByQuota,
        'deletedOrphans': deletedOrphans,
        'finalSizeBytes': finalSizeBytes,
      });
    } catch (e, stack) {
      _logStructured('ERROR', 'Error during set-based cleanup, attempting fallback recovery', {
        'error': e.toString(),
        'stack': stack.toString(),
      });
      await _executeFallbackCleanup(cutoffTimestamp, maxRows);
    }
  }

  /// Calculates total database size in bytes via SQLite pragmas.
  Future<int> _getDatabaseSizeBytes() async {
    try {
      final pageCountRow = await customSelect('PRAGMA page_count;').getSingle();
      final pageSizeRow = await customSelect('PRAGMA page_size;').getSingle();
      final pageCount = pageCountRow.data.values.first as int;
      final pageSize = pageSizeRow.data.values.first as int;
      return pageCount * pageSize;
    } catch (_) {
      return 0;
    }
  }

  /// Fallback recovery path if atomic transaction fails.
  Future<void> _executeFallbackCleanup(int cutoffTimestamp, int maxRows) async {
    try {
      await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();
      final countExpr = notificationsTable.id.count();
      final countRow = await (selectOnly(notificationsTable)..addColumns([countExpr])).getSingle();
      final currentCount = countRow.read(countExpr) ?? 0;
      if (currentCount > maxRows) {
        final keepQuery = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id])
          ..orderBy([OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.desc)])
          ..limit(maxRows);
        await (delete(notificationsTable)..where((t) => t.id.isNotInQuery(keepQuery))).go();
      }
      final keepNotificationIds = selectOnly(notificationsTable)..addColumns([notificationsTable.id]);
      await (delete(reviewQueueTable)..where((t) => t.notificationId.isNotInQuery(keepNotificationIds))).go();
      _logStructured('FALLBACK_COMPLETE', 'Fallback cleanup executed successfully', {});
    } catch (e) {
      _logStructured('FALLBACK_ERROR', 'Fallback cleanup failed', {'error': e.toString()});
    }
  }

  void _logStructured(String event, String message, Map<String, dynamic> data) {
    if (kDebugMode) {
      debugPrint('[StorageGovernance] [$event] $message | ${data.toString()}');
    }
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file, setup: (rawDb) {
      try {
        rawDb.execute('PRAGMA auto_vacuum = INCREMENTAL;');
        rawDb.execute('PRAGMA journal_mode = WAL;');
      } catch (_) {}
    });
  });
}
