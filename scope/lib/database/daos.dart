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

class StorageStats {
  final int totalNotifications;
  final double estimatedSizeMb;
  final int maxStorageMb;
  final int maxRowCap;

  const StorageStats({
    required this.totalNotifications,
    required this.estimatedSizeMb,
    required this.maxStorageMb,
    required this.maxRowCap,
  });
}

@DriftAccessor(tables: [UserSettingsTable, NotificationsTable])
class UserSettingsDao extends DatabaseAccessor<AttentionDatabase> with _$UserSettingsDaoMixin {
  UserSettingsDao(super.db);

  static const List<int> allowedRetentionDays = [3, 7, 14, 30, -1];
  static const List<int> allowedStorageMb = [10, 25, 50, 100, -1];

  Future<UserSettingsEntry> getSettings() async {
    final existing = await (select(userSettingsTable)..where((t) => t.id.equals(1))).getSingleOrNull();
    if (existing != null) {
      return existing;
    }
    const defaultSettings = UserSettingsEntry(
      id: 1,
      retentionDays: 7,
      telemetryEnabled: true,
      maxRowCap: 5000,
      maxStorageMb: 25,
    );
    await into(userSettingsTable).insert(defaultSettings, mode: InsertMode.insertOrReplace);
    return defaultSettings;
  }

  Stream<UserSettingsEntry> watchSettings() {
    return (select(userSettingsTable)..where((t) => t.id.equals(1)))
        .watchSingleOrNull()
        .map((entry) =>
            entry ??
            const UserSettingsEntry(
              id: 1,
              retentionDays: 7,
              telemetryEnabled: true,
              maxRowCap: 5000,
              maxStorageMb: 25,
            ));
  }

  Future<void> updateSettings({
    int? retentionDays,
    bool? telemetryEnabled,
    int? maxRowCap,
    int? maxStorageMb,
  }) async {
    final current = await getSettings();

    // Validation & Sanitization Guardrails
    int validatedRetention = current.retentionDays;
    if (retentionDays != null) {
      if (allowedRetentionDays.contains(retentionDays) || retentionDays > 0) {
        validatedRetention = retentionDays;
      } else {
        validatedRetention = 7; // Default fallback
      }
    }

    bool validatedTelemetry = telemetryEnabled ?? current.telemetryEnabled;

    int validatedRowCap = current.maxRowCap;
    if (maxRowCap != null) {
      if (maxRowCap == -1 || maxRowCap > 0) {
        validatedRowCap = maxRowCap;
      } else {
        validatedRowCap = 5000; // Default fallback
      }
    }

    int validatedStorageMb = current.maxStorageMb;
    if (maxStorageMb != null) {
      if (allowedStorageMb.contains(maxStorageMb) || maxStorageMb == -1 || maxStorageMb > 0) {
        validatedStorageMb = maxStorageMb;
      } else {
        validatedStorageMb = 25; // Default fallback
      }
    }

    final updated = current.copyWith(
      retentionDays: validatedRetention,
      telemetryEnabled: validatedTelemetry,
      maxRowCap: validatedRowCap,
      maxStorageMb: validatedStorageMb,
    );

    await update(userSettingsTable).replace(updated);
  }

  Future<StorageStats> getStorageStats() async {
    final settings = await getSettings();
    final count = await db.notificationDao.getCount();
    // Estimate average notification size (~1.5 KB)
    final estimatedMb = (count * 1500) / (1024 * 1024);
    return StorageStats(
      totalNotifications: count,
      estimatedSizeMb: double.parse(estimatedMb.toStringAsFixed(2)),
      maxStorageMb: settings.maxStorageMb,
      maxRowCap: settings.maxRowCap,
    );
  }
}

