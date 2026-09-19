import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/telemetry_governance_engine.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/tables.dart';

part 'daos.g.dart';

@DriftAccessor(tables: [NotificationsTable])
class NotificationDao extends DatabaseAccessor<AttentionDatabase> with _$NotificationDaoMixin {
  NotificationDao(super.db);

  Future<void> insertNotification(NotificationEntry entry) async {
    await into(notificationsTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<void> insertAll(List<NotificationEntry> entries) async {
    await batch((b) {
      b.insertAll(notificationsTable, entries, mode: InsertMode.insertOrReplace);
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
  final TelemetryGovernanceEngine? _governanceEngine;

  FocusSessionDao(super.db, [TelemetryGovernanceEngine? governanceEngine])
      : _governanceEngine = governanceEngine;

  TelemetryGovernanceEngine get engine => _governanceEngine ?? TelemetryGovernanceEngine();

  Future<void> insertSession(FocusSessionEntry entry) async {
    final governed = engine.governFocusSession(entry);
    await into(focusSessionsTable).insert(governed);
  }

  Future<FocusSessionEntry?> getActiveSession() {
    return (select(focusSessionsTable)..where((t) => t.sessionEnd.isNull())).getSingleOrNull();
  }

  Future<void> updateSession(FocusSessionEntry entry) async {
    final governed = engine.governFocusSession(entry);
    await update(focusSessionsTable).replace(governed);
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
  final TelemetryGovernanceEngine? _governanceEngine;

  DailyBriefDao(super.db, [TelemetryGovernanceEngine? governanceEngine])
      : _governanceEngine = governanceEngine;

  TelemetryGovernanceEngine get engine => _governanceEngine ?? TelemetryGovernanceEngine();

  Future<void> insertOrUpdate(DailyBriefEntry entry, {TelemetryGovernanceEngine? governanceEngine}) async {
    final gov = governanceEngine ?? engine;
    final governed = gov.governDailyBrief(entry);
    await into(dailyBriefTable).insert(governed, mode: InsertMode.insertOrReplace);
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
    TelemetryGovernanceEngine? governanceEngine,
  }) async {
    final gov = governanceEngine ?? engine;

    final noisedReviewed = reviewed != 0 ? gov.applyLaplaceNoise(reviewed) : 0;
    final noisedCompleted = completed != 0 ? gov.applyLaplaceNoise(completed) : 0;
    final noisedCalendar = calendar != 0 ? gov.applyLaplaceNoise(calendar) : 0;
    final noisedReminders = reminders != 0 ? gov.applyLaplaceNoise(reminders) : 0;
    final noisedArchived = archived != 0 ? gov.applyLaplaceNoise(archived) : 0;

    final existing = await getBriefForDate(date);
    if (existing != null) {
      await update(dailyBriefTable).replace(existing.copyWith(
        notificationsReviewed: existing.notificationsReviewed + noisedReviewed,
        actionsCompleted: existing.actionsCompleted + noisedCompleted,
        calendarEventsCreated: existing.calendarEventsCreated + noisedCalendar,
        remindersCreated: existing.remindersCreated + noisedReminders,
        archivedCount: existing.archivedCount + noisedArchived,
      ));
    } else {
      await into(dailyBriefTable).insert(DailyBriefEntry(
        id: 0,
        date: date,
        notificationsReviewed: noisedReviewed,
        actionsCompleted: noisedCompleted,
        calendarEventsCreated: noisedCalendar,
        remindersCreated: noisedReminders,
        archivedCount: noisedArchived,
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
