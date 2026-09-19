import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_budget_engine.dart';
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

  /// Budget-aware aggregate query method.
  Future<PrivacyQueryResult<FocusSessionAggregateStats>> getBudgetAwareAggregateStats(
    PrivacyBudgetEngine engine, {
    double epsilonQuery = 0.1,
  }) async {
    final sessions = await getAll();
    int rawTotalDuration = 0;
    int rawTotalInterruptions = 0;
    for (final s in sessions) {
      rawTotalDuration += s.duration;
      rawTotalInterruptions += s.interruptions;
    }

    final durationRes = await engine.evaluateIntQuery(
      rawValue: rawTotalDuration,
      sensitivity: 3600.0,
      epsilonQuery: epsilonQuery / 2,
      minVal: 0,
    );

    final interruptionsRes = await engine.evaluateIntQuery(
      rawValue: rawTotalInterruptions,
      sensitivity: 10.0,
      epsilonQuery: epsilonQuery / 2,
      minVal: 0,
    );

    return PrivacyQueryResult<FocusSessionAggregateStats>(
      value: FocusSessionAggregateStats(
        totalDurationSeconds: durationRes.value,
        totalInterruptions: interruptionsRes.value,
        sessionCount: sessions.length,
      ),
      bucketInterval: durationRes.isFallback ? 'Coarsened Fallback' : 'Laplace Noise Injected',
      isFallback: durationRes.isFallback || interruptionsRes.isFallback,
      remainingBudget: engine.remainingBudget,
      consumedEpsilon: engine.consumedEpsilon,
    );
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

  /// Budget-aware aggregate query method for a specific date.
  Future<PrivacyQueryResult<DailyBriefEntry>> getBudgetAwareBriefForDate(
    String date,
    PrivacyBudgetEngine engine, {
    double epsilonQuery = 0.1,
  }) async {
    final brief = await getBriefForDate(date) ??
        DailyBriefEntry(
          id: 0,
          date: date,
          notificationsReviewed: 0,
          actionsCompleted: 0,
          calendarEventsCreated: 0,
          remindersCreated: 0,
          archivedCount: 0,
        );

    final reviewedRes = await engine.evaluateIntQuery(
      rawValue: brief.notificationsReviewed,
      sensitivity: 1.0,
      epsilonQuery: epsilonQuery / 5,
      minVal: 0,
    );
    final completedRes = await engine.evaluateIntQuery(
      rawValue: brief.actionsCompleted,
      sensitivity: 1.0,
      epsilonQuery: epsilonQuery / 5,
      minVal: 0,
    );
    final calendarRes = await engine.evaluateIntQuery(
      rawValue: brief.calendarEventsCreated,
      sensitivity: 1.0,
      epsilonQuery: epsilonQuery / 5,
      minVal: 0,
    );
    final remindersRes = await engine.evaluateIntQuery(
      rawValue: brief.remindersCreated,
      sensitivity: 1.0,
      epsilonQuery: epsilonQuery / 5,
      minVal: 0,
    );
    final archivedRes = await engine.evaluateIntQuery(
      rawValue: brief.archivedCount,
      sensitivity: 1.0,
      epsilonQuery: epsilonQuery / 5,
      minVal: 0,
    );

    final noisyBrief = brief.copyWith(
      notificationsReviewed: reviewedRes.value,
      actionsCompleted: completedRes.value,
      calendarEventsCreated: calendarRes.value,
      remindersCreated: remindersRes.value,
      archivedCount: archivedRes.value,
    );

    return PrivacyQueryResult<DailyBriefEntry>(
      value: noisyBrief,
      bucketInterval: reviewedRes.isFallback ? 'Coarsened Fallback' : 'Laplace Noise Injected',
      isFallback: reviewedRes.isFallback,
      remainingBudget: engine.remainingBudget,
      consumedEpsilon: engine.consumedEpsilon,
    );
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

@DriftAccessor(tables: [PrivacyBudgetTable])
class PrivacyBudgetDao extends DatabaseAccessor<AttentionDatabase> with _$PrivacyBudgetDaoMixin {
  PrivacyBudgetDao(super.db);

  Future<PrivacyBudgetEntry?> getBudgetForDate(String epochDate) {
    return (select(privacyBudgetTable)..where((t) => t.epochDate.equals(epochDate))).getSingleOrNull();
  }

  Future<void> insertOrUpdateBudget(PrivacyBudgetEntry entry) async {
    await into(privacyBudgetTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<void> updateConsumedEpsilon(String epochDate, double consumed) async {
    final existing = await getBudgetForDate(epochDate);
    if (existing != null) {
      await (update(privacyBudgetTable)..where((t) => t.epochDate.equals(epochDate)))
          .write(PrivacyBudgetTableCompanion(consumedEpsilon: Value(consumed)));
    } else {
      await into(privacyBudgetTable).insert(PrivacyBudgetEntry(
        id: 0,
        epochDate: epochDate,
        targetEpsilon: 1.0,
        consumedEpsilon: consumed,
      ));
    }
  }

  Future<List<PrivacyBudgetEntry>> getAll() {
    return select(privacyBudgetTable).get();
  }

  Future<void> clearAll() async {
    await delete(privacyBudgetTable).go();
  }
}
