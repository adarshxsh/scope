import 'dart:math';
import 'package:drift/drift.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/tables.dart';

part 'daos.g.dart';

/// Helper class for generating Laplace noise for Differential Privacy.
class LaplaceNoise {
  final double epsilon;
  final Random _random;

  LaplaceNoise({this.epsilon = 1.0, Random? random})
      : _random = random ?? Random();

  /// Draw a random sample from Laplace(0, b) where scale b = 1.0 / epsilon.
  double sample() {
    final b = 1.0 / epsilon;
    double u = _random.nextDouble();
    while (u <= 0.0 || u >= 1.0) {
      u = _random.nextDouble();
    }
    if (u <= 0.5) {
      return b * log(2 * u);
    } else {
      return -b * log(2 * (1 - u));
    }
  }

  /// Adds Laplace noise to [rawValue] and rounds to the nearest integer.
  int addNoise(int rawValue) {
    return (rawValue + sample()).round();
  }
}

/// Helper functions for Telemetry Sanitization & Aggregation.
class TelemetrySanitizer {
  /// Rounds a DateTime to the nearest 1-hour boundary.
  static DateTime roundToNearestHour(DateTime dt) {
    if (dt.minute >= 30) {
      final hourAdded = dt.add(const Duration(hours: 1));
      return DateTime(
        hourAdded.year,
        hourAdded.month,
        hourAdded.day,
        hourAdded.hour,
      );
    } else {
      return DateTime(
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
      );
    }
  }

  /// Aggregates focus session duration in seconds into discrete 60-minute windows (3600s blocks).
  static int bucketDurationToHourly(int seconds) {
    if (seconds <= 0) return 0;
    final blocks = (seconds / 3600.0).round();
    return blocks * 3600;
  }
}

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

  FocusSessionEntry _sanitizeEntry(FocusSessionEntry entry) {
    final sanitizedStart = TelemetrySanitizer.roundToNearestHour(entry.sessionStart);
    final sanitizedEnd = entry.sessionEnd != null
        ? TelemetrySanitizer.roundToNearestHour(entry.sessionEnd!)
        : null;
    final sanitizedDuration = TelemetrySanitizer.bucketDurationToHourly(entry.duration);

    return entry.copyWith(
      sessionStart: sanitizedStart,
      sessionEnd: sanitizedEnd != null ? Value(sanitizedEnd) : const Value.absent(),
      duration: sanitizedDuration,
    );
  }

  Future<void> insertSession(FocusSessionEntry entry) async {
    await into(focusSessionsTable).insert(_sanitizeEntry(entry));
  }

  Future<FocusSessionEntry?> getActiveSession() {
    return (select(focusSessionsTable)..where((t) => t.sessionEnd.isNull())).getSingleOrNull();
  }

  Future<void> updateSession(FocusSessionEntry entry) async {
    await update(focusSessionsTable).replace(_sanitizeEntry(entry));
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
  DailyBriefDao(super.db, {LaplaceNoise? noise})
      : laplaceNoise = noise ?? LaplaceNoise(epsilon: 1.0);

  final LaplaceNoise laplaceNoise;

  DailyBriefEntry _clamp(DailyBriefEntry entry) {
    return entry.copyWith(
      notificationsReviewed: max(0, entry.notificationsReviewed),
      actionsCompleted: max(0, entry.actionsCompleted),
      calendarEventsCreated: max(0, entry.calendarEventsCreated),
      remindersCreated: max(0, entry.remindersCreated),
      archivedCount: max(0, entry.archivedCount),
    );
  }

  Future<void> insertOrUpdate(DailyBriefEntry entry) async {
    final noisyEntry = entry.copyWith(
      notificationsReviewed: laplaceNoise.addNoise(entry.notificationsReviewed),
      actionsCompleted: laplaceNoise.addNoise(entry.actionsCompleted),
      calendarEventsCreated: laplaceNoise.addNoise(entry.calendarEventsCreated),
      remindersCreated: laplaceNoise.addNoise(entry.remindersCreated),
      archivedCount: laplaceNoise.addNoise(entry.archivedCount),
    );
    await into(dailyBriefTable).insert(noisyEntry, mode: InsertMode.insertOrReplace);
  }

  Future<DailyBriefEntry?> getBriefForDate(String date) async {
    final entry = await (select(dailyBriefTable)..where((t) => t.date.equals(date))).getSingleOrNull();
    if (entry == null) return null;
    return _clamp(entry);
  }

  Future<void> incrementStats(
    String date, {
    int reviewed = 0,
    int completed = 0,
    int calendar = 0,
    int reminders = 0,
    int archived = 0,
  }) async {
    final existing = await (select(dailyBriefTable)..where((t) => t.date.equals(date))).getSingleOrNull();
    if (existing != null) {
      final updatedReviewed = reviewed != 0 ? existing.notificationsReviewed + laplaceNoise.addNoise(reviewed) : existing.notificationsReviewed;
      final updatedCompleted = completed != 0 ? existing.actionsCompleted + laplaceNoise.addNoise(completed) : existing.actionsCompleted;
      final updatedCalendar = calendar != 0 ? existing.calendarEventsCreated + laplaceNoise.addNoise(calendar) : existing.calendarEventsCreated;
      final updatedReminders = reminders != 0 ? existing.remindersCreated + laplaceNoise.addNoise(reminders) : existing.remindersCreated;
      final updatedArchived = archived != 0 ? existing.archivedCount + laplaceNoise.addNoise(archived) : existing.archivedCount;

      await update(dailyBriefTable).replace(existing.copyWith(
        notificationsReviewed: updatedReviewed,
        actionsCompleted: updatedCompleted,
        calendarEventsCreated: updatedCalendar,
        remindersCreated: updatedReminders,
        archivedCount: updatedArchived,
      ));
    } else {
      await into(dailyBriefTable).insert(DailyBriefEntry(
        id: 0,
        date: date,
        notificationsReviewed: laplaceNoise.addNoise(reviewed),
        actionsCompleted: laplaceNoise.addNoise(completed),
        calendarEventsCreated: laplaceNoise.addNoise(calendar),
        remindersCreated: laplaceNoise.addNoise(reminders),
        archivedCount: laplaceNoise.addNoise(archived),
      ));
    }
  }

  Future<List<DailyBriefEntry>> getAll() async {
    final list = await select(dailyBriefTable).get();
    return list.map(_clamp).toList();
  }

  Future<void> clearAll() async {
    await delete(dailyBriefTable).go();
  }
}

