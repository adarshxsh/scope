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

  /// Runs a single-step atomic transaction to clean up expired notifications (older than 7 days),
  /// historical focus sessions (older than 30 days), daily briefs (older than 30 days),
  /// and any orphaned review queue entries, avoiding main-thread loops.
  Future<void> runSetBasedCleanup(
    int cutoffTimestamp, {
    int? retentionCutoffTimestamp,
  }) async {
    await transaction(() async {
      // 1. Delete expired notifications based on cutoff timestamp
      await (delete(notificationsTable)..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp))).go();

      // 2. Delete orphaned review queue entries in a set-based query
      final orphanedQuery = delete(reviewQueueTable)..where((t) {
        final hasNotification = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id]);
        return t.notificationId.isNotInQuery(hasNotification);
      });
      await orphanedQuery.go();

      // 3. Delete focus sessions older than 30 days
      final cutoff30DaysMs = retentionCutoffTimestamp ??
          DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      final cutoff30DaysDateTime = DateTime.fromMillisecondsSinceEpoch(cutoff30DaysMs);

      await (delete(focusSessionsTable)
            ..where((t) => t.sessionStart.isSmallerThanValue(cutoff30DaysDateTime)))
          .go();

      // 4. Delete daily brief entries older than 30 days
      final dateStr =
          '${cutoff30DaysDateTime.year.toString().padLeft(4, '0')}-${cutoff30DaysDateTime.month.toString().padLeft(2, '0')}-${cutoff30DaysDateTime.day.toString().padLeft(2, '0')}';
      await (delete(dailyBriefTable)..where((t) => t.date.isSmallerThanValue(dateStr))).go();
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
