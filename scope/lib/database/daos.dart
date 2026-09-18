import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/sync/crdt.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/tables.dart';

part 'daos.g.dart';

@DriftAccessor(tables: [NotificationsTable, ReviewQueueTable])
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

  Future<void> mergeNotificationStateDelta(NotificationStateDelta remoteDelta) async {
    final localEntry = await getById(remoteDelta.notificationId);
    if (localEntry == null) {
      final newEntry = NotificationEntry(
        id: remoteDelta.notificationId,
        packageName: 'unknown',
        title: '',
        content: '',
        timestamp: remoteDelta.timestamp,
        isOngoing: false,
        state: remoteDelta.state,
        snoozedUntil: remoteDelta.snoozedUntil,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(remoteDelta.timestamp, isUtc: true),
        reviewed: remoteDelta.state == ReviewState.REVIEWED,
        dismissed: remoteDelta.state == ReviewState.ARCHIVED,
        createdAt: DateTime.fromMillisecondsSinceEpoch(remoteDelta.timestamp, isUtc: true),
        vectorClock: remoteDelta.vectorClock.toJson(),
        originDeviceId: remoteDelta.originDeviceId,
        syncTimestamp: DateTime.fromMillisecondsSinceEpoch(remoteDelta.timestamp, isUtc: true),
      );
      await into(notificationsTable).insert(newEntry, mode: InsertMode.insertOrReplace);
      return;
    }

    final localVc = VectorClock.fromJson(localEntry.vectorClock ?? '{}');
    final localTimestamp = localEntry.syncTimestamp?.millisecondsSinceEpoch ??
        localEntry.lastUpdated?.millisecondsSinceEpoch ??
        localEntry.timestamp;
    final localDelta = NotificationStateDelta(
      notificationId: localEntry.id,
      state: localEntry.state,
      snoozedUntil: localEntry.snoozedUntil,
      originDeviceId: localEntry.originDeviceId ?? '',
      vectorClock: localVc,
      timestamp: localTimestamp,
    );

    final winningDelta = CrdtStateResolver.resolveNotificationDelta(localDelta, remoteDelta);

    await (update(notificationsTable)..where((t) => t.id.equals(remoteDelta.notificationId))).write(
      NotificationsTableCompanion(
        state: Value(winningDelta.state),
        snoozedUntil: Value(winningDelta.snoozedUntil),
        vectorClock: Value(winningDelta.vectorClock.toJson()),
        originDeviceId: Value(winningDelta.originDeviceId),
        syncTimestamp: Value(DateTime.fromMillisecondsSinceEpoch(winningDelta.timestamp, isUtc: true)),
        lastUpdated: Value(DateTime.now().toUtc()),
      ),
    );

    await (update(db.reviewQueueTable)..where((t) => t.notificationId.equals(remoteDelta.notificationId))).write(
      ReviewQueueTableCompanion(
        status: Value(winningDelta.state),
        vectorClock: Value(winningDelta.vectorClock.toJson()),
        originDeviceId: Value(winningDelta.originDeviceId),
        syncTimestamp: Value(DateTime.fromMillisecondsSinceEpoch(winningDelta.timestamp, isUtc: true)),
      ),
    );
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

@DriftAccessor(tables: [RlhfRulesTable])
class RlhfRulesDao extends DatabaseAccessor<AttentionDatabase> with _$RlhfRulesDaoMixin {
  RlhfRulesDao(super.db);

  Future<void> insertOrUpdateRule(RlhfRuleEntry entry) async {
    await into(rlhfRulesTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<RlhfRuleEntry?> getRuleById(String id) {
    return (select(rlhfRulesTable)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<RlhfRuleEntry>> getAllActiveRules() {
    return (select(rlhfRulesTable)..where((t) => t.isDeleted.equals(false))).get();
  }

  Future<List<RlhfRuleEntry>> getAllRules() {
    return select(rlhfRulesTable).get();
  }

  Future<void> mergeRlhfRuleDelta(RlhfRuleDelta remoteDelta) async {
    final localEntry = await getRuleById(remoteDelta.ruleId);
    if (localEntry == null) {
      if (remoteDelta.rule == null && remoteDelta.isDeleted) return;
      final newEntry = RlhfRuleEntry(
        id: remoteDelta.ruleId,
        category: remoteDelta.rule?.category ?? '',
        priority: remoteDelta.rule?.priority ?? '',
        conditionsJson: json.encode(remoteDelta.rule?.conditions.toMap() ?? {}),
        isDeleted: remoteDelta.isDeleted,
        originDeviceId: remoteDelta.originDeviceId,
        vectorClock: remoteDelta.vectorClock.toJson(),
        syncTimestamp: DateTime.fromMillisecondsSinceEpoch(remoteDelta.timestamp, isUtc: true),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(remoteDelta.timestamp, isUtc: true),
      );
      await into(rlhfRulesTable).insert(newEntry, mode: InsertMode.insertOrReplace);
      return;
    }

    final localVc = VectorClock.fromJson(localEntry.vectorClock ?? '{}');
    final localTimestamp = localEntry.syncTimestamp?.millisecondsSinceEpoch ?? localEntry.updatedAt.millisecondsSinceEpoch;

    NotificationRule? localRule;
    if (localEntry.conditionsJson.isNotEmpty) {
      try {
        final map = json.decode(localEntry.conditionsJson) as Map<String, dynamic>;
        localRule = NotificationRule(
          id: localEntry.id,
          category: localEntry.category,
          priority: localEntry.priority,
          conditions: RuleCondition.fromMap(map),
        );
      } catch (_) {}
    }

    final localDelta = RlhfRuleDelta(
      ruleId: localEntry.id,
      rule: localRule,
      isDeleted: localEntry.isDeleted,
      originDeviceId: localEntry.originDeviceId ?? '',
      vectorClock: localVc,
      timestamp: localTimestamp,
    );

    final winningDelta = CrdtStateResolver.resolveRuleDelta(localDelta, remoteDelta);
    final winningRule = winningDelta.rule ?? remoteDelta.rule ?? localRule;

    await (update(rlhfRulesTable)..where((t) => t.id.equals(remoteDelta.ruleId))).write(
      RlhfRulesTableCompanion(
        category: Value(winningRule?.category ?? localEntry.category),
        priority: Value(winningRule?.priority ?? localEntry.priority),
        conditionsJson: Value(json.encode(winningRule?.conditions.toMap() ?? {})),
        isDeleted: Value(winningDelta.isDeleted),
        vectorClock: Value(winningDelta.vectorClock.toJson()),
        originDeviceId: Value(winningDelta.originDeviceId),
        syncTimestamp: Value(DateTime.fromMillisecondsSinceEpoch(winningDelta.timestamp, isUtc: true)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> clearAll() async {
    await delete(rlhfRulesTable).go();
  }
}

@DriftAccessor(tables: [OfflineSyncQueueTable])
class OfflineSyncQueueDao extends DatabaseAccessor<AttentionDatabase> with _$OfflineSyncQueueDaoMixin {
  OfflineSyncQueueDao(super.db);

  Future<int> enqueue(OfflineSyncQueueTableCompanion entry) async {
    return into(offlineSyncQueueTable).insert(entry);
  }

  Future<List<OfflineSyncQueueEntry>> getPendingItems() {
    return (select(offlineSyncQueueTable)
          ..where((t) => t.isSynced.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
        .get();
  }

  Future<void> markSynced(int id) async {
    await (update(offlineSyncQueueTable)..where((t) => t.id.equals(id)))
        .write(const OfflineSyncQueueTableCompanion(isSynced: Value(true)));
  }

  Future<void> clearAll() async {
    await delete(offlineSyncQueueTable).go();
  }
}
