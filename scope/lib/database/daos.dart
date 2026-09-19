import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/tables.dart';

part 'daos.g.dart';

@DriftAccessor(tables: [NotificationsTable])
class NotificationDao extends DatabaseAccessor<AttentionDatabase> with _$NotificationDaoMixin {
  static const int defaultMaxCapacity = 1000;

  NotificationDao(super.db);

  Future<void> insertNotification(
    NotificationEntry entry, {
    int maxCapacity = defaultMaxCapacity,
  }) async {
    await db.transaction(() async {
      await into(notificationsTable).insert(entry, mode: InsertMode.insertOrReplace);
      await _enforceMaxCapacity(maxCapacity);
    });
  }

  Future<void> insertAll(
    List<NotificationEntry> entries, {
    int maxCapacity = defaultMaxCapacity,
  }) async {
    if (entries.isEmpty) return;
    await db.transaction(() async {
      await batch((b) {
        b.insertAll(notificationsTable, entries, mode: InsertMode.insertOrReplace);
      });
      await _enforceMaxCapacity(maxCapacity);
    });
  }

  Future<NotificationEntry?> getById(String id) {
    return (select(notificationsTable)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<NotificationEntry>> getAll() {
    return (select(notificationsTable)
          ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
        .get();
  }

  Stream<List<NotificationEntry>> watchAll() {
    return (select(notificationsTable)
          ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)]))
        .watch();
  }

  Future<int> deleteOlderThan(int cutoffTimestamp) async {
    return await db.transaction(() async {
      final deleted = await (delete(notificationsTable)
            ..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp)))
          .go();
      await db.cleanupOrphanedReviewQueue();
      return deleted;
    });
  }

  Future<void> clearAll() async {
    await db.transaction(() async {
      await delete(notificationsTable).go();
      await db.cleanupOrphanedReviewQueue();
    });
  }

  Future<int> getCount() async {
    final countExpr = notificationsTable.id.count();
    final query = selectOnly(notificationsTable)..addColumns([countExpr]);
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  Future<void> _enforceMaxCapacity(int maxCapacity) async {
    if (maxCapacity <= 0) return;
    final totalCount = await getCount();
    if (totalCount <= maxCapacity) return;

    final excess = totalCount - maxCapacity;

    await customUpdate(
      '''
      DELETE FROM notifications_table
      WHERE id IN (
        SELECT id FROM notifications_table
        ORDER BY 
          CASE WHEN (state = 'ACTIVE' AND (reviewed = 0 OR reviewed IS NULL) AND (priority = 'critical' OR priority = 'high')) THEN 1 ELSE 0 END ASC,
          timestamp ASC
        LIMIT ?
      )
      ''',
      variables: [Variable.withInt(excess)],
      updates: {notificationsTable},
    );

    await db.cleanupOrphanedReviewQueue();
  }
}

@DriftAccessor(tables: [ReviewQueueTable])
class ReviewQueueDao extends DatabaseAccessor<AttentionDatabase> with _$ReviewQueueDaoMixin {
  ReviewQueueDao(super.db);

  Future<void> insertItem(ReviewQueueEntry entry) async {
    await into(reviewQueueTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<List<ReviewQueueEntry>> getAll() {
    return select(reviewQueueTable).get();
  }

  Future<int> deleteItem(String notificationId) {
    return (delete(reviewQueueTable)..where((t) => t.notificationId.equals(notificationId))).go();
  }

  Future<void> clearAll() async {
    await delete(reviewQueueTable).go();
  }

  Future<int> updateStatus(String notificationId, ReviewState state) {
    return (update(reviewQueueTable)..where((t) => t.notificationId.equals(notificationId)))
        .write(ReviewQueueTableCompanion(status: Value(state)));
  }
}

@DriftAccessor(tables: [FocusSessionsTable])
class FocusSessionDao extends DatabaseAccessor<AttentionDatabase> with _$FocusSessionDaoMixin {
  FocusSessionDao(super.db);

  Future<void> insertSession(FocusSessionEntry entry) async {
    await into(focusSessionsTable).insert(entry);
  }

  Future<FocusSessionEntry?> getActiveSession() {
    return (select(focusSessionsTable)..where((t) => t.sessionEnd.isNull())).getSingleOrNull();
  }

  Future<void> updateSession(FocusSessionEntry entry) async {
    await update(focusSessionsTable).replace(entry);
  }

  Future<List<FocusSessionEntry>> getAll() {
    return select(focusSessionsTable).get();
  }

  Future<void> clearAll() async {
    await delete(focusSessionsTable).go();
  }
}

@DriftAccessor(tables: [DailyBriefTable])
class DailyBriefDao extends DatabaseAccessor<AttentionDatabase> with _$DailyBriefDaoMixin {
  DailyBriefDao(super.db);

  Future<void> insertOrUpdate(DailyBriefEntry entry) async {
    await into(dailyBriefTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<DailyBriefEntry?> getBriefForDate(String date) {
    return (select(dailyBriefTable)..where((t) => t.date.equals(date))).getSingleOrNull();
  }

  Future<void> incrementStats(
    String date, {
    int reviewed = 0,
    int completed = 0,
    int calendar = 0,
    int reminders = 0,
    int archived = 0,
  }) async {
    final existing = await getBriefForDate(date);
    if (existing != null) {
      await update(dailyBriefTable).replace(existing.copyWith(
        notificationsReviewed: existing.notificationsReviewed + reviewed,
        actionsCompleted: existing.actionsCompleted + completed,
        calendarEventsCreated: existing.calendarEventsCreated + calendar,
        remindersCreated: existing.remindersCreated + reminders,
        archivedCount: existing.archivedCount + archived,
      ));
    } else {
      await into(dailyBriefTable).insert(DailyBriefEntry(
        id: 0,
        date: date,
        notificationsReviewed: reviewed,
        actionsCompleted: completed,
        calendarEventsCreated: calendar,
        remindersCreated: reminders,
        archivedCount: archived,
      ));
    }
  }

  Future<List<DailyBriefEntry>> getAll() {
    return select(dailyBriefTable).get();
  }

  Future<void> clearAll() async {
    await delete(dailyBriefTable).go();
  }
}
