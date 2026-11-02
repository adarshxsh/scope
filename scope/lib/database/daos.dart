import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/tables.dart';

part 'daos.g.dart';

@DriftAccessor(tables: [NotificationsTable, ReviewQueueTable])
class NotificationDao extends DatabaseAccessor<AttentionDatabase> with _$NotificationDaoMixin {
  NotificationDao(super.db);

  static const int maxNotificationLimit = 5000;

  Future<void> insertNotification(NotificationEntry entry, {int maxLimit = maxNotificationLimit}) async {
    await into(notificationsTable).insert(entry, mode: InsertMode.insertOrReplace);
    await _enforceCapacityLimit(maxLimit);
  }

  Future<void> insertAll(List<NotificationEntry> entries, {int maxLimit = maxNotificationLimit}) async {
    if (entries.isEmpty) return;
    await batch((b) {
      b.insertAll(notificationsTable, entries, mode: InsertMode.insertOrReplace);
    });
    await _enforceCapacityLimit(maxLimit);
  }

  Future<void> _enforceCapacityLimit(int maxLimit) async {
    try {
      final currentCount = await getCount();
      if (currentCount <= maxLimit) return;

      final excess = currentCount - maxLimit;

      final evictionTier = CustomExpression<int>(
        "CASE "
        "WHEN state IN ('ARCHIVED', 'REVIEWED', 'EXPIRED') OR reviewed = 1 OR dismissed = 1 THEN 0 "
        "WHEN priority IS NULL OR priority != 'critical' THEN 1 "
        "ELSE 2 "
        "END",
      );

      final query = selectOnly(notificationsTable)
        ..addColumns([notificationsTable.id])
        ..orderBy([
          OrderingTerm(expression: evictionTier, mode: OrderingMode.asc),
          OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc),
        ])
        ..limit(excess);

      final rows = await query.get();
      final idsToDelete = rows.map((r) => r.read(notificationsTable.id)!).toList();

      if (idsToDelete.isEmpty) return;

      await transaction(() async {
        for (var i = 0; i < idsToDelete.length; i += 500) {
          final chunk = idsToDelete.sublist(
            i,
            i + 500 > idsToDelete.length ? idsToDelete.length : i + 500,
          );
          await (delete(reviewQueueTable)..where((t) => t.notificationId.isIn(chunk))).go();
          await (delete(notificationsTable)..where((t) => t.id.isIn(chunk))).go();
        }
      });
    } catch (e) {
      if (e.toString().toLowerCase().contains('close')) return;
      rethrow;
    }
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

  Future<int> deleteOlderThan(int cutoffTimestamp) {
    return (delete(notificationsTable)
          ..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp)))
        .go();
  }

  Future<void> clearAll() async {
    await delete(notificationsTable).go();
  }

  Future<int> getCount() async {
    final countExpr = notificationsTable.id.count();
    final query = selectOnly(notificationsTable)..addColumns([countExpr]);
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
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
