import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/tables.dart';

part 'daos.g.dart';

const int defaultMaxNotificationCapacity = 1000;

@DriftAccessor(tables: [NotificationsTable, ReviewQueueTable])
class NotificationDao extends DatabaseAccessor<AttentionDatabase> with _$NotificationDaoMixin {
  final int maxCapacity;
  int? _cachedCount;

  NotificationDao(super.db, {this.maxCapacity = defaultMaxNotificationCapacity});

  Future<void> insertNotification(NotificationEntry entry) async {
    await into(notificationsTable).insert(entry, mode: InsertMode.insertOrReplace);
    _cachedCount = (_cachedCount ?? 0) + 1;

    if (_cachedCount! > maxCapacity) {
      await enforceCapacityLimit();
    }
  }

  Future<void> insertAll(List<NotificationEntry> entries) async {
    if (entries.isEmpty) return;
    await batch((b) {
      b.insertAll(notificationsTable, entries, mode: InsertMode.insertOrReplace);
    });
    _cachedCount = (_cachedCount ?? 0) + entries.length;

    if (_cachedCount! > maxCapacity) {
      await enforceCapacityLimit();
    }
  }

  /// Verifies table entry counts and executes an immediate set-based FIFO eviction
  /// of the oldest entries ordered by timestamp if capacity is exceeded.
  /// Also deletes orphaned review queue records in the same transaction.
  Future<void> enforceCapacityLimit() async {
    final count = await getCount();
    _cachedCount = count;
    if (count > maxCapacity) {
      final excess = count - maxCapacity;
      await db.transaction(() async {
        // Select IDs of the oldest entries exceeding capacity ceiling
        final oldestSubquery = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id])
          ..orderBy([
            OrderingTerm(expression: notificationsTable.timestamp, mode: OrderingMode.asc),
            OrderingTerm(expression: notificationsTable.id, mode: OrderingMode.asc),
          ])
          ..limit(excess);

        // Set-based FIFO deletion of the oldest entries
        await (delete(notificationsTable)
              ..where((t) => t.id.isInQuery(oldestSubquery)))
            .go();

        // Set-based cleanup of orphaned review queue items in the same write transaction
        final hasNotification = selectOnly(notificationsTable)
          ..addColumns([notificationsTable.id]);
        await (db.delete(db.reviewQueueTable)
              ..where((t) => t.notificationId.isNotInQuery(hasNotification)))
            .go();
      });
      _cachedCount = maxCapacity;
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
