import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/telemetry/telemetry_governance_service.dart';
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
  final TelemetryGovernanceService governanceService;

  FocusSessionDao(super.db, [TelemetryGovernanceService? governanceService])
      : governanceService = governanceService ?? TelemetryGovernanceService();

  Future<void> insertSession(FocusSessionEntry entry) async {
    final sanitized = governanceService.sanitizeFocusSession(entry);
    if (sanitized.id == 0) {
      await into(focusSessionsTable).insert(
        FocusSessionsTableCompanion.insert(
          sessionStart: sanitized.sessionStart,
          sessionEnd: Value(sanitized.sessionEnd),
          interruptions: Value(sanitized.interruptions),
          completion: Value(sanitized.completion),
          duration: sanitized.duration,
        ),
      );
    } else {
      await into(focusSessionsTable).insert(sanitized);
    }
  }

  Future<FocusSessionEntry?> getActiveSession() {
    return (select(focusSessionsTable)..where((t) => t.sessionEnd.isNull())).getSingleOrNull();
  }

  Future<void> updateSession(FocusSessionEntry entry) async {
    final sanitized = governanceService.sanitizeFocusSession(entry);
    await update(focusSessionsTable).replace(sanitized);
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
  final TelemetryGovernanceService governanceService;

  DailyBriefDao(super.db, [TelemetryGovernanceService? governanceService])
      : governanceService = governanceService ?? TelemetryGovernanceService();

  Future<void> insertOrUpdate(DailyBriefEntry entry) async {
    final transformed = governanceService.transformDailyBrief(entry);
    if (transformed.id == 0) {
      await into(dailyBriefTable).insert(
        DailyBriefTableCompanion.insert(
          date: transformed.date,
          notificationsReviewed: Value(transformed.notificationsReviewed),
          actionsCompleted: Value(transformed.actionsCompleted),
          calendarEventsCreated: Value(transformed.calendarEventsCreated),
          remindersCreated: Value(transformed.remindersCreated),
          archivedCount: Value(transformed.archivedCount),
        ),
        mode: InsertMode.insertOrReplace,
      );
    } else {
      await into(dailyBriefTable).insert(transformed, mode: InsertMode.insertOrReplace);
    }
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
      final updated = existing.copyWith(
        notificationsReviewed: existing.notificationsReviewed + reviewed,
        actionsCompleted: existing.actionsCompleted + completed,
        calendarEventsCreated: existing.calendarEventsCreated + calendar,
        remindersCreated: existing.remindersCreated + reminders,
        archivedCount: existing.archivedCount + archived,
      );
      final transformed = governanceService.transformDailyBrief(updated);
      await update(dailyBriefTable).replace(transformed);
    } else {
      final newEntry = DailyBriefEntry(
        id: 0,
        date: date,
        notificationsReviewed: reviewed,
        actionsCompleted: completed,
        calendarEventsCreated: calendar,
        remindersCreated: reminders,
        archivedCount: archived,
      );
      final transformed = governanceService.transformDailyBrief(newEntry);
      await into(dailyBriefTable).insert(
        DailyBriefTableCompanion.insert(
          date: transformed.date,
          notificationsReviewed: Value(transformed.notificationsReviewed),
          actionsCompleted: Value(transformed.actionsCompleted),
          calendarEventsCreated: Value(transformed.calendarEventsCreated),
          remindersCreated: Value(transformed.remindersCreated),
          archivedCount: Value(transformed.archivedCount),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<List<DailyBriefEntry>> getAll() {
    return select(dailyBriefTable).get();
  }

  Future<void> clearAll() async {
    await delete(dailyBriefTable).go();
  }
}
