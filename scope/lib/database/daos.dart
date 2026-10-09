import 'dart:math';
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
  final PrivacyBudgetManager? _privacyBudgetManager;

  FocusSessionDao(super.db, [PrivacyBudgetManager? privacyBudgetManager])
      : _privacyBudgetManager = privacyBudgetManager;

  PrivacyBudgetManager get privacyBudgetManager =>
      _privacyBudgetManager ?? PrivacyBudgetManager(db: attachedDatabase);

  Future<bool> insertSession(
    FocusSessionEntry entry, {
    double? opEpsilon,
    Random? random,
    bool injectNoise = false,
  }) async {
    final pbm = _privacyBudgetManager;
    final shouldInject = injectNoise || pbm != null || opEpsilon != null;

    if (shouldInject) {
      final manager = pbm ?? PrivacyBudgetManager(db: attachedDatabase);
      final eps = opEpsilon ?? PrivacyBudgetManager.defaultOpEpsilon;

      final budgetConsumed = await manager.consumeBudget(eps);
      if (!budgetConsumed) {
        // Budget exhausted! Suppress write.
        return false;
      }

      final noisyDuration = manager.applyNoisyDuration(
        entry.duration,
        epsilon: eps,
        random: random,
      );
      final noisyInterruptions = manager.applyNoisyInterruptions(
        entry.interruptions,
        epsilon: eps,
        random: random,
      );

      final noisyEntry = entry.copyWith(
        duration: noisyDuration,
        interruptions: noisyInterruptions,
      );

      await into(focusSessionsTable).insert(noisyEntry);
      return true;
    }

    await into(focusSessionsTable).insert(entry);
    return true;
  }

  Future<FocusSessionEntry?> getActiveSession() {
    return (select(focusSessionsTable)..where((t) => t.sessionEnd.isNull())).getSingleOrNull();
  }

  Future<bool> updateSession(
    FocusSessionEntry entry, {
    double? opEpsilon,
    Random? random,
    bool injectNoise = false,
  }) async {
    final pbm = _privacyBudgetManager;
    final shouldInject = injectNoise || pbm != null || opEpsilon != null;

    if (shouldInject) {
      final manager = pbm ?? PrivacyBudgetManager(db: attachedDatabase);
      final eps = opEpsilon ?? PrivacyBudgetManager.defaultOpEpsilon;

      final budgetConsumed = await manager.consumeBudget(eps);
      if (!budgetConsumed) {
        // Budget exhausted! Suppress write.
        return false;
      }

      final noisyDuration = manager.applyNoisyDuration(
        entry.duration,
        epsilon: eps,
        random: random,
      );
      final noisyInterruptions = manager.applyNoisyInterruptions(
        entry.interruptions,
        epsilon: eps,
        random: random,
      );

      final noisyEntry = entry.copyWith(
        duration: noisyDuration,
        interruptions: noisyInterruptions,
      );

      await update(focusSessionsTable).replace(noisyEntry);
      return true;
    }

    await update(focusSessionsTable).replace(entry);
    return true;
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
  final PrivacyBudgetManager? _privacyBudgetManager;

  DailyBriefDao(super.db, [PrivacyBudgetManager? privacyBudgetManager])
      : _privacyBudgetManager = privacyBudgetManager;

  PrivacyBudgetManager get privacyBudgetManager =>
      _privacyBudgetManager ?? PrivacyBudgetManager(db: attachedDatabase);

  Future<bool> insertOrUpdate(
    DailyBriefEntry entry, {
    double? opEpsilon,
    Random? random,
    bool injectNoise = false,
  }) async {
    final pbm = _privacyBudgetManager;
    final shouldInject = injectNoise || pbm != null || opEpsilon != null;

    if (shouldInject) {
      final manager = pbm ?? PrivacyBudgetManager(db: attachedDatabase);
      final eps = opEpsilon ?? PrivacyBudgetManager.defaultOpEpsilon;

      final budgetConsumed = await manager.consumeBudget(eps);
      if (!budgetConsumed) {
        // Budget exhausted! Suppress write.
        return false;
      }

      final noisyEntry = entry.copyWith(
        notificationsReviewed: manager.applyNoisyCount(entry.notificationsReviewed, epsilon: eps, random: random),
        actionsCompleted: manager.applyNoisyCount(entry.actionsCompleted, epsilon: eps, random: random),
        calendarEventsCreated: manager.applyNoisyCount(entry.calendarEventsCreated, epsilon: eps, random: random),
        remindersCreated: manager.applyNoisyCount(entry.remindersCreated, epsilon: eps, random: random),
        archivedCount: manager.applyNoisyCount(entry.archivedCount, epsilon: eps, random: random),
      );

      await into(dailyBriefTable).insert(noisyEntry, mode: InsertMode.insertOrReplace);
      return true;
    }

    await into(dailyBriefTable).insert(entry, mode: InsertMode.insertOrReplace);
    return true;
  }

  Future<DailyBriefEntry?> getBriefForDate(String date) {
    return (select(dailyBriefTable)..where((t) => t.date.equals(date))).getSingleOrNull();
  }

  Future<bool> incrementStats(
    String date, {
    int reviewed = 0,
    int completed = 0,
    int calendar = 0,
    int reminders = 0,
    int archived = 0,
    double? opEpsilon,
    Random? random,
    bool injectNoise = false,
  }) async {
    final pbm = _privacyBudgetManager;
    final shouldInject = injectNoise || pbm != null || opEpsilon != null;

    if (shouldInject) {
      final manager = pbm ?? PrivacyBudgetManager(db: attachedDatabase);
      final eps = opEpsilon ?? PrivacyBudgetManager.defaultOpEpsilon;

      final budgetConsumed = await manager.consumeBudget(eps);
      if (!budgetConsumed) {
        // Budget exhausted! Suppress write.
        return false;
      }

      final noisyReviewed = reviewed > 0 ? manager.applyNoisyCount(reviewed, epsilon: eps, random: random) : 0;
      final noisyCompleted = completed > 0 ? manager.applyNoisyCount(completed, epsilon: eps, random: random) : 0;
      final noisyCalendar = calendar > 0 ? manager.applyNoisyCount(calendar, epsilon: eps, random: random) : 0;
      final noisyReminders = reminders > 0 ? manager.applyNoisyCount(reminders, epsilon: eps, random: random) : 0;
      final noisyArchived = archived > 0 ? manager.applyNoisyCount(archived, epsilon: eps, random: random) : 0;

      final existing = await getBriefForDate(date);
      if (existing != null) {
        await update(dailyBriefTable).replace(existing.copyWith(
          notificationsReviewed: existing.notificationsReviewed + noisyReviewed,
          actionsCompleted: existing.actionsCompleted + noisyCompleted,
          calendarEventsCreated: existing.calendarEventsCreated + noisyCalendar,
          remindersCreated: existing.remindersCreated + noisyReminders,
          archivedCount: existing.archivedCount + noisyArchived,
        ));
      } else {
        await into(dailyBriefTable).insert(DailyBriefEntry(
          id: 0,
          date: date,
          notificationsReviewed: noisyReviewed,
          actionsCompleted: noisyCompleted,
          calendarEventsCreated: noisyCalendar,
          remindersCreated: noisyReminders,
          archivedCount: noisyArchived,
        ));
      }
      return true;
    }

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
    return true;
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

  Future<PrivacyBudgetEntry?> getEntryForDate(String date) {
    return (select(privacyBudgetTable)..where((t) => t.date.equals(date))).getSingleOrNull();
  }

  Future<void> upsertEntry(PrivacyBudgetEntry entry) async {
    await into(privacyBudgetTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<List<PrivacyBudgetEntry>> getAll() {
    return select(privacyBudgetTable).get();
  }

  Future<void> clearAll() async {
    await delete(privacyBudgetTable).go();
  }
}
