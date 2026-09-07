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

  /// Runs a single-step atomic transaction to clean up expired notifications
  /// based on cutoff timestamp, enforce max row count caps, delete orphaned review
  /// queue entries, and execute SQLite disk compaction (VACUUM).
  Future<void> runSetBasedCleanup(
    int cutoffTimestamp, {
    int maxRows = 500,
    bool compact = true,
  }) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      await (delete(notificationsTable)
            ..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp)))
          .go();

      // 2. Enforce maximum row count caps
      final countExpr = notificationsTable.id.count();
      final countQuery = selectOnly(notificationsTable)..addColumns([countExpr]);
      final totalRow = await countQuery.getSingle();
      int currentCount = totalRow.read(countExpr) ?? 0;

      if (currentCount > maxRows) {
        // Prune auto-expired items first
        int excess = currentCount - maxRows;
        final deletedExpired = await _deleteOldestInState(ReviewState.EXPIRED, excess);
        currentCount -= deletedExpired;

        // Prune archived items next
        if (currentCount > maxRows) {
          excess = currentCount - maxRows;
          final deletedArchived = await _deleteOldestInState(ReviewState.ARCHIVED, excess);
          currentCount -= deletedArchived;

          // Prune reviewed items next
          if (currentCount > maxRows) {
            excess = currentCount - maxRows;
            await _deleteOldestInState(ReviewState.REVIEWED, excess);
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

    // 4. Compact database disk storage (outside transaction)
    if (compact) {
      try {
        await customStatement('VACUUM;');
      } catch (_) {
        // Silently handle exceptions during vacuum (e.g., in-memory or locked DB)
      }
    }
  }

  Future<int> _deleteOldestInState(ReviewState targetState, int maxToDelete) async {
    if (maxToDelete <= 0) return 0;
    final subquery = selectOnly(notificationsTable)
      ..addColumns([notificationsTable.id])
      ..where(notificationsTable.state.equals(targetState.name))
      ..orderBy([OrderingTerm.asc(notificationsTable.timestamp)])
      ..limit(maxToDelete);
    return await (delete(notificationsTable)..where((t) => t.id.isInQuery(subquery))).go();
  }
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'attention_os.db'));
    return NativeDatabase(file);
  });
}
