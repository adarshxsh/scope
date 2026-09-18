import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
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

@DriftAccessor(tables: [UserSettingsTable])
class UserSettingsDao extends DatabaseAccessor<AttentionDatabase> with _$UserSettingsDaoMixin {
  UserSettingsDao(super.db);

  Future<UserSettingsEntry> getUserSettings() async {
    final settings = await (select(userSettingsTable)..where((t) => t.id.equals(1))).getSingleOrNull();
    if (settings != null) return settings;

    final defaultSettings = UserSettingsEntry(
      id: 1,
      retentionDays: 7,
      telemetryEnabled: true,
      storageQuotaMb: 25,
      maxRowCap: 5000,
      lastUpdated: DateTime.now(),
    );
    await into(userSettingsTable).insert(defaultSettings, mode: InsertMode.insertOrReplace);
    return defaultSettings;
  }

  Future<void> updateUserSettings({
    int? retentionDays,
    bool? telemetryEnabled,
    int? storageQuotaMb,
    int? maxRowCap,
  }) async {
    final current = await getUserSettings();

    // Enforce strict validation boundaries
    int validRetention = current.retentionDays;
    if (retentionDays != null) {
      if (retentionDays == -1 || (retentionDays >= 1 && retentionDays <= 365)) {
        validRetention = retentionDays;
      }
    }

    final validTelemetry = telemetryEnabled ?? current.telemetryEnabled;

    int validQuota = current.storageQuotaMb;
    if (storageQuotaMb != null && storageQuotaMb >= 5 && storageQuotaMb <= 500) {
      validQuota = storageQuotaMb;
    }

    int validCap = current.maxRowCap;
    if (maxRowCap != null && maxRowCap >= 100 && maxRowCap <= 50000) {
      validCap = maxRowCap;
    }

    final updated = current.copyWith(
      retentionDays: validRetention,
      telemetryEnabled: validTelemetry,
      storageQuotaMb: validQuota,
      maxRowCap: validCap,
      lastUpdated: Value(DateTime.now()),
    );
    await into(userSettingsTable).insert(updated, mode: InsertMode.insertOrReplace);
  }
}

@DriftAccessor(tables: [InferenceTelemetryTable])
class InferenceTelemetryDao extends DatabaseAccessor<AttentionDatabase> with _$InferenceTelemetryDaoMixin {
  InferenceTelemetryDao(super.db);

  Future<void> logEvent(Insertable<InferenceTelemetryEntry> entry) async {
    final settings = await db.userSettingsDao.getUserSettings();
    if (!settings.telemetryEnabled) return; // Gracefully bypass if disabled

    await into(inferenceTelemetryTable).insert(entry);
  }

  Future<int> getTelemetryCount() async {
    final countExpr = inferenceTelemetryTable.id.count();
    final query = selectOnly(inferenceTelemetryTable)..addColumns([countExpr]);
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  Future<int> deleteOlderThan(int cutoffTimestamp) {
    return (delete(inferenceTelemetryTable)
          ..where((t) => t.timestamp.isSmallerThanValue(cutoffTimestamp)))
        .go();
  }

  Future<void> clearAll() async {
    await delete(inferenceTelemetryTable).go();
  }

  Future<List<InferenceTelemetryEntry>> getRecentEvents([int limit = 50]) {
    return (select(inferenceTelemetryTable)
          ..orderBy([(t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
  }
}
