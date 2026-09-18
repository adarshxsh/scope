import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/sync/crdt.dart';
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

  Future<void> mergeNotificationStateDelta(NotificationStateDelta delta) async {
    final existing = await getById(delta.notificationId);
    if (existing != null) {
      final localDelta = NotificationStateDelta(
        notificationId: existing.id,
        state: existing.state,
        snoozedUntil: existing.snoozedUntil,
        originDeviceId: existing.originDeviceId ?? '',
        vectorClock: VectorClock.fromJson(existing.vectorClock ?? '{}'),
        timestamp: existing.syncTimestamp?.millisecondsSinceEpoch ?? 0,
      );

      final resolved = CrdtStateResolver.resolveNotificationDelta(localDelta, delta);

      await (update(notificationsTable)..where((t) => t.id.equals(delta.notificationId))).write(
        NotificationsTableCompanion(
          state: Value(resolved.state),
          snoozedUntil: Value(resolved.snoozedUntil),
          vectorClock: Value(resolved.vectorClock.toJson()),
          originDeviceId: Value(resolved.originDeviceId),
          syncTimestamp: Value(DateTime.fromMillisecondsSinceEpoch(resolved.timestamp, isUtc: true)),
          lastUpdated: Value(DateTime.fromMillisecondsSinceEpoch(resolved.timestamp, isUtc: true)),
        ),
      );

      await db.reviewQueueDao.updateStatus(delta.notificationId, resolved.state);
    }
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

@DriftAccessor(tables: [RlhfRulesTable])
class RlhfRulesDao extends DatabaseAccessor<AttentionDatabase> with _$RlhfRulesDaoMixin {
  RlhfRulesDao(super.db);

  Future<List<RlhfRuleEntry>> getRules() {
    return (select(rlhfRulesTable)..where((t) => t.isDeleted.equals(false))).get();
  }

  Future<void> insertOrUpdateRule(RlhfRuleEntry entry) async {
    await into(rlhfRulesTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<void> deleteRule(String id) async {
    await (update(rlhfRulesTable)..where((t) => t.id.equals(id)))
        .write(const RlhfRulesTableCompanion(isDeleted: Value(true)));
  }

  Future<void> mergeRlhfRuleDelta(RlhfRuleDelta delta) async {
    final existing = await (select(rlhfRulesTable)..where((t) => t.id.equals(delta.ruleId))).getSingleOrNull();

    if (existing != null) {
      RuleCondition cond = const RuleCondition();
      try {
        final Map<String, dynamic> condMap = json.decode(existing.conditionsJson) as Map<String, dynamic>;
        cond = RuleCondition.fromMap(condMap);
      } catch (_) {}

      final localDelta = RlhfRuleDelta(
        ruleId: existing.id,
        rule: NotificationRule(
          id: existing.id,
          category: existing.category,
          priority: existing.priority,
          conditions: cond,
        ),
        isDeleted: existing.isDeleted,
        originDeviceId: existing.originDeviceId ?? '',
        vectorClock: VectorClock.fromJson(existing.vectorClock ?? '{}'),
        timestamp: existing.syncTimestamp?.millisecondsSinceEpoch ?? 0,
      );

      final resolved = CrdtStateResolver.resolveRuleDelta(localDelta, delta);

      await (update(rlhfRulesTable)..where((t) => t.id.equals(delta.ruleId))).write(
        RlhfRulesTableCompanion(
          isDeleted: Value(resolved.isDeleted),
          originDeviceId: Value(resolved.originDeviceId),
          vectorClock: Value(resolved.vectorClock.toJson()),
          syncTimestamp: Value(DateTime.fromMillisecondsSinceEpoch(resolved.timestamp, isUtc: true)),
          updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(resolved.timestamp, isUtc: true)),
        ),
      );
    } else {
      await into(rlhfRulesTable).insert(
        RlhfRuleEntry(
          id: delta.ruleId,
          category: delta.rule?.category ?? '',
          priority: delta.rule?.priority ?? 'high',
          conditionsJson: json.encode(delta.rule?.conditions.toMap() ?? {}),
          isDeleted: delta.isDeleted,
          originDeviceId: delta.originDeviceId,
          vectorClock: delta.vectorClock.toJson(),
          syncTimestamp: DateTime.fromMillisecondsSinceEpoch(delta.timestamp, isUtc: true),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(delta.timestamp, isUtc: true),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }
}

@DriftAccessor(tables: [OfflineSyncQueueTable])
class OfflineSyncQueueDao extends DatabaseAccessor<AttentionDatabase> with _$OfflineSyncQueueDaoMixin {
  OfflineSyncQueueDao(super.db);

  Future<void> enqueue(OfflineSyncQueueTableCompanion entry) async {
    await into(offlineSyncQueueTable).insert(entry);
  }

  Future<List<OfflineSyncQueueEntry>> getPendingItems() {
    return (select(offlineSyncQueueTable)..where((t) => t.isSynced.equals(false))).get();
  }

  Future<void> markSynced(int id) async {
    await (update(offlineSyncQueueTable)..where((t) => t.id.equals(id)))
        .write(const OfflineSyncQueueTableCompanion(isSynced: Value(true)));
  }
}

@DriftAccessor(tables: [PrivacyLedgerTable])
class PrivacyLedgerDao extends DatabaseAccessor<AttentionDatabase> with _$PrivacyLedgerDaoMixin {
  PrivacyLedgerDao(super.db);

  Future<void> recordQueryConsumption(String date, double epsilon, double delta) async {
    final existingList = await (select(privacyLedgerTable)..where((t) => t.date.equals(date))).get();
    if (existingList.isNotEmpty) {
      final existing = existingList.first;
      await update(privacyLedgerTable).replace(existing.copyWith(
        epsilonSpent: existing.epsilonSpent + epsilon,
        deltaSpent: existing.deltaSpent + delta,
        queryCount: existing.queryCount + 1,
        lastUpdated: DateTime.now(),
      ));
    } else {
      await into(privacyLedgerTable).insert(PrivacyLedgerTableCompanion.insert(
        date: date,
        epsilonSpent: Value(epsilon),
        deltaSpent: Value(delta),
        queryCount: const Value(1),
        lastUpdated: Value(DateTime.now()),
      ));
    }
  }

  Future<void> recordRemoteConsumption(String date, double epsilon, double delta) async {
    await recordQueryConsumption(date, epsilon, delta);
  }

  Future<double> getEpsilonSpentForDate(String date) async {
    final query = select(privacyLedgerTable)..where((t) => t.date.equals(date));
    final rows = await query.get();
    return rows.fold<double>(0.0, (sum, row) => sum + row.epsilonSpent);
  }

  Future<double> getEpsilonSpentForMonth(String monthPrefix) async {
    final query = select(privacyLedgerTable)..where((t) => t.date.like('$monthPrefix%'));
    final rows = await query.get();
    return rows.fold<double>(0.0, (sum, row) => sum + row.epsilonSpent);
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
