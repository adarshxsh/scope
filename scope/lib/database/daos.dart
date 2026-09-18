import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/telemetry/telemetry_governance_service.dart';
import 'package:scope/core/utils/pii_redactor.dart';
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
    final sanitizedEntry = entry.copyWith(
      duration: TelemetryGovernanceService.quantizeDuration(entry.duration),
      interruptions: TelemetryGovernanceService.quantizeInterruptions(entry.interruptions),
    );
    await into(focusSessionsTable).insert(sanitizedEntry);
  }

  Future<FocusSessionEntry?> getActiveSession() {
    return (select(focusSessionsTable)..where((t) => t.sessionEnd.isNull())).getSingleOrNull();
  }

  Future<void> updateSession(FocusSessionEntry entry) async {
    final sanitizedEntry = entry.copyWith(
      duration: TelemetryGovernanceService.quantizeDuration(entry.duration),
      interruptions: TelemetryGovernanceService.quantizeInterruptions(entry.interruptions),
    );
    await update(focusSessionsTable).replace(sanitizedEntry);
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

@DriftAccessor(tables: [
  InferenceTelemetryTable,
  InferenceAuditLogsTable,
  PrivacyBudgetTable,
  PrivacyLedgerTable,
])
class InferenceTelemetryDao extends DatabaseAccessor<AttentionDatabase> with _$InferenceTelemetryDaoMixin {
  InferenceTelemetryDao(super.db);

  Future<void> insertTelemetry(InferenceTelemetryEntry entry) async {
    final quantizedEntry = entry.copyWith(
      quantizedTimestamp: TelemetryGovernanceService.quantizeTimestamp(entry.quantizedTimestamp),
    );
    await into(inferenceTelemetryTable).insert(quantizedEntry);
  }

  Future<void> insertAuditLog({
    required int timestamp,
    required String eventType,
    required String logMessage,
  }) async {
    final redactedMessage = PiiRedactor.redact(logMessage);
    await into(inferenceAuditLogsTable).insert(
      InferenceAuditLogsTableCompanion.insert(
        timestamp: timestamp,
        eventType: eventType,
        logMessage: redactedMessage,
      ),
    );
  }

  Future<List<InferenceTelemetryEntry>> getAllTelemetry() {
    return select(inferenceTelemetryTable).get();
  }

  Future<List<InferenceAuditLogEntry>> getAllAuditLogs() {
    return select(inferenceAuditLogsTable).get();
  }

  Future<PrivacyBudgetEntry?> getPrivacyBudget(String entity) {
    return (select(privacyBudgetTable)..where((t) => t.entity.equals(entity))).getSingleOrNull();
  }

  Future<void> updatePrivacyBudget(PrivacyBudgetEntry entry) async {
    await into(privacyBudgetTable).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<void> recordLedgerEntry(PrivacyLedgerEntry entry) async {
    await into(privacyLedgerTable).insert(entry);
  }

  Future<void> clearAll() async {
    await delete(inferenceTelemetryTable).go();
    await delete(inferenceAuditLogsTable).go();
    await delete(privacyBudgetTable).go();
    await delete(privacyLedgerTable).go();
  }
}

