import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
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

  /// Queries total focus duration in seconds with sensitivity-calibrated Laplace noise applied.
  /// Enforces maximum duration clipping per session (S_duration = 120s) to bound sensitivity.
  Future<NoisedQueryResult<int>> getNoisedTotalFocusDuration(
    PrivacyBudgetManager budgetManager, {
    double sensitivity = 120.0,
    double? epsilon,
  }) async {
    return budgetManager.executeNoisedQuery<int>(
      sensitivity: sensitivity,
      epsilon: epsilon,
      exactQuery: () async {
        final sessions = await getAll();
        final maxSeconds = sensitivity.toInt() > 0 ? sensitivity.toInt() : 120;
        return sessions.fold<int>(0, (sum, s) => sum + s.duration.clamp(0, maxSeconds));
      },
    );
  }

  /// Queries total focus interruptions with sensitivity clipping applied.
  Future<NoisedQueryResult<int>> getNoisedFocusInterruptions(
    PrivacyBudgetManager budgetManager, {
    double sensitivity = 5.0,
    double? epsilon,
  }) async {
    return budgetManager.executeNoisedQuery<int>(
      sensitivity: sensitivity,
      epsilon: epsilon,
      exactQuery: () async {
        final sessions = await getAll();
        final maxInter = sensitivity.toInt() > 0 ? sensitivity.toInt() : 5;
        return sessions.fold<int>(0, (sum, s) => sum + s.interruptions.clamp(0, maxInter));
      },
    );
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

  /// Queries daily reviewed notification count with sensitivity-calibrated Laplace noise applied (sensitivity = 1.0).
  Future<NoisedQueryResult<int>> getNoisedReviewedCount(
    PrivacyBudgetManager budgetManager,
    String date, {
    double? epsilon,
  }) async {
    return budgetManager.executeNoisedQuery<int>(
      sensitivity: 1.0,
      epsilon: epsilon,
      exactQuery: () async {
        final brief = await getBriefForDate(date);
        return brief?.notificationsReviewed ?? 0;
      },
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

@DriftAccessor(tables: [PrivacyLedgerTable])
class PrivacyLedgerDao extends DatabaseAccessor<AttentionDatabase> with _$PrivacyLedgerDaoMixin {
  PrivacyLedgerDao(super.db);

  Future<double> getEpsilonSpentForDate(String date) async {
    final query = select(privacyLedgerTable)..where((t) => t.date.equals(date));
    final entries = await query.get();
    return entries.fold<double>(0.0, (sum, item) => sum + item.epsilonSpent);
  }

  Future<double> getEpsilonSpentForMonth(String monthPrefix) async {
    final query = select(privacyLedgerTable)..where((t) => t.date.like('$monthPrefix%'));
    final entries = await query.get();
    return entries.fold<double>(0.0, (sum, item) => sum + item.epsilonSpent);
  }

  Future<void> recordQueryConsumption(String date, double epsilon, double delta) async {
    final query = select(privacyLedgerTable)..where((t) => t.date.equals(date));
    final existing = await query.getSingleOrNull();
    final now = DateTime.now();

    if (existing != null) {
      await update(privacyLedgerTable).replace(
        existing.copyWith(
          epsilonSpent: existing.epsilonSpent + epsilon,
          deltaSpent: existing.deltaSpent + delta,
          queryCount: existing.queryCount + 1,
          lastUpdated: now,
        ),
      );
    } else {
      await into(privacyLedgerTable).insert(
        PrivacyLedgerEntry(
          id: 0,
          date: date,
          epsilonSpent: epsilon,
          deltaSpent: delta,
          queryCount: 1,
          lastUpdated: now,
        ),
      );
    }
  }

  Future<List<PrivacyLedgerEntry>> getAll() {
    return select(privacyLedgerTable).get();
  }

  Future<void> clearAll() async {
    await delete(privacyLedgerTable).go();
  }
}
