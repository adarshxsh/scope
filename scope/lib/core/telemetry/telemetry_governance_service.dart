import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:scope/database/attention_database.dart';

/// Represents a raw or processed telemetry event.
class TelemetryEvent {
  final String eventType;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  TelemetryEvent({
    required this.eventType,
    this.metadata = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Formal telemetry schema specification that enforces registered event types
/// and allowed metadata attributes.
class TelemetrySchema {
  final Map<String, Set<String>> _registeredEvents;

  TelemetrySchema(this._registeredEvents);

  factory TelemetrySchema.defaultSchema() {
    return TelemetrySchema({
      'focus_session_start': {
        'sessionStart',
        'timestamp',
      },
      'focus_session_end': {
        'sessionStart',
        'sessionEnd',
        'duration',
        'interruptions',
        'completion',
        'timestamp',
      },
      'daily_metrics_update': {
        'date',
        'notificationsReviewed',
        'actionsCompleted',
        'calendarEventsCreated',
        'remindersCreated',
        'archivedCount',
        'timestamp',
      },
      'notification_reviewed': {'date', 'count', 'timestamp'},
      'action_completed': {'date', 'count', 'timestamp'},
      'calendar_event_created': {'date', 'count', 'timestamp'},
      'reminder_created': {'date', 'count', 'timestamp'},
      'archived': {'date', 'count', 'timestamp'},
    });
  }

  bool isRegisteredEventType(String eventType) {
    return _registeredEvents.containsKey(eventType);
  }

  bool areMetadataAttributesApproved(String eventType, Map<String, dynamic> metadata) {
    final allowed = _registeredEvents[eventType];
    if (allowed == null) return false;
    for (final key in metadata.keys) {
      if (!allowed.contains(key)) return false;
    }
    return true;
  }

  void validate(TelemetryEvent event) {
    if (!isRegisteredEventType(event.eventType)) {
      throw ArgumentError('Unregistered telemetry event type: ${event.eventType}');
    }
    if (!areMetadataAttributesApproved(event.eventType, event.metadata)) {
      final allowed = _registeredEvents[event.eventType];
      final unapproved = event.metadata.keys.where((k) => !allowed!.contains(k)).toList();
      throw ArgumentError('Unapproved metadata attributes for event "${event.eventType}": $unapproved');
    }
  }
}

/// Telemetry Governance Service providing on-device Laplacian differential privacy
/// noise injection and 15-minute timestamp bucketing for focus sessions and daily metrics.
class TelemetryGovernanceService {
  final AttentionDatabase _db;
  final double epsilon;
  final double sensitivity;
  final math.Random? _random;
  final TelemetrySchema _schema;

  TelemetryGovernanceService({
    required AttentionDatabase db,
    double epsilon = 1.0,
    double sensitivity = 1.0,
    math.Random? random,
    TelemetrySchema? schema,
  })  : _db = db,
        epsilon = epsilon,
        sensitivity = sensitivity,
        _random = random,
        _schema = schema ?? TelemetrySchema.defaultSchema() {
    if (epsilon <= 0 || (epsilon > 10.0 && !epsilon.isInfinite)) {
      throw ArgumentError('Epsilon must be bounded within (0, 10.0] or double.infinity. Given: $epsilon');
    }
  }

  /// Laplace distribution scale parameter: b = sensitivity / epsilon
  double get scale => epsilon.isInfinite ? 0.0 : sensitivity / epsilon;

  /// Quantizes a timestamp to the nearest 15-minute discrete boundary.
  static DateTime quantizeTimestamp(DateTime dt) {
    final utc = dt.toUtc();
    final ms = utc.millisecondsSinceEpoch;
    const intervalMs = 15 * 60 * 1000; // 900,000 ms = 15 mins
    final quantizedMs = (ms / intervalMs).round() * intervalMs;
    final quantizedUtc = DateTime.fromMillisecondsSinceEpoch(quantizedMs, isUtc: true);
    return dt.isUtc ? quantizedUtc : quantizedUtc.toLocal();
  }

  /// Quantizes duration in seconds to 15-minute discrete buckets.
  /// Durations < 15 minutes (900s) are rounded to nearest 15 minutes (900s minimum for non-zero sessions).
  static int quantizeDurationSeconds(int rawDurationSeconds) {
    if (rawDurationSeconds <= 0) return 0;
    const bucketSeconds = 15 * 60; // 900 seconds
    final buckets = (rawDurationSeconds / bucketSeconds).round();
    return math.max(1, buckets) * bucketSeconds;
  }

  /// Samples Laplacian noise Lap(scale) on-device using inverse transform sampling.
  double sampleLaplaceNoise({double? customScale}) {
    final s = customScale ?? scale;
    if (s == 0.0) return 0.0;
    final rng = _random ?? math.Random();
    double u = rng.nextDouble() - 0.5;
    while (u == 0 || u.abs() >= 0.5) {
      u = rng.nextDouble() - 0.5;
    }
    final sign = u < 0 ? -1.0 : 1.0;
    return -s * sign * math.log(1.0 - 2.0 * u.abs());
  }

  /// Applies Laplace noise and non-negative lower-bound post-processing.
  int applyLaplaceNoise(int value, {double? customScale}) {
    final noise = sampleLaplaceNoise(customScale: customScale);
    final noisyValue = (value + noise).round();
    return math.max(0, noisyValue);
  }

  /// Validates and logs a telemetry event against schema rules.
  void logEvent(TelemetryEvent event) {
    _schema.validate(event);
  }

  /// Focus Session: Start a session with 15-minute quantized start timestamp.
  Future<void> startFocusSession(DateTime startTime) async {
    final quantizedStart = quantizeTimestamp(startTime);

    logEvent(TelemetryEvent(
      eventType: 'focus_session_start',
      metadata: {
        'sessionStart': quantizedStart.toIso8601String(),
        'timestamp': startTime.toIso8601String(),
      },
      timestamp: startTime,
    ));

    await _db.focusSessionDao.insertSession(FocusSessionEntry(
      id: 0,
      sessionStart: quantizedStart,
      interruptions: 0,
      completion: false,
      duration: 0,
    ));
  }

  /// Focus Session: Finish active focus session, quantizing timestamps and duration.
  Future<void> finishFocusSession({
    required DateTime startTime,
    required DateTime endTime,
    int interruptions = 0,
    bool completion = true,
  }) async {
    final quantizedStart = quantizeTimestamp(startTime);
    var quantizedEnd = quantizeTimestamp(endTime);
    final rawDurationSeconds = endTime.difference(startTime).inSeconds;
    final quantizedDuration = quantizeDurationSeconds(rawDurationSeconds);

    if (!quantizedEnd.isAfter(quantizedStart)) {
      quantizedEnd = quantizedStart.add(Duration(seconds: math.max(900, quantizedDuration)));
    }

    logEvent(TelemetryEvent(
      eventType: 'focus_session_end',
      metadata: {
        'sessionStart': quantizedStart.toIso8601String(),
        'sessionEnd': quantizedEnd.toIso8601String(),
        'duration': quantizedDuration,
        'interruptions': interruptions,
        'completion': completion,
        'timestamp': endTime.toIso8601String(),
      },
      timestamp: endTime,
    ));

    final activeSession = await _db.focusSessionDao.getActiveSession();
    if (activeSession != null) {
      await _db.focusSessionDao.updateSession(activeSession.copyWith(
        sessionStart: quantizedStart,
        sessionEnd: Value(quantizedEnd),
        completion: completion,
        duration: quantizedDuration,
        interruptions: interruptions,
      ));
    } else {
      await _db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 0,
        sessionStart: quantizedStart,
        sessionEnd: quantizedEnd,
        interruptions: interruptions,
        completion: completion,
        duration: quantizedDuration,
      ));
    }
  }

  /// Records daily metrics with Differential Privacy Laplace noise and non-negative lower bound post-processing.
  Future<void> recordDailyBriefStats(
    String date, {
    int notificationsReviewed = 0,
    int actionsCompleted = 0,
    int calendarEventsCreated = 0,
    int remindersCreated = 0,
    int archivedCount = 0,
  }) async {
    logEvent(TelemetryEvent(
      eventType: 'daily_metrics_update',
      metadata: {
        'date': date,
        'notificationsReviewed': notificationsReviewed,
        'actionsCompleted': actionsCompleted,
        'calendarEventsCreated': calendarEventsCreated,
        'remindersCreated': remindersCreated,
        'archivedCount': archivedCount,
      },
    ));

    final existing = await _db.dailyBriefDao.getBriefForDate(date);

    final noisyReviewed = applyLaplaceNoise(notificationsReviewed);
    final noisyActions = applyLaplaceNoise(actionsCompleted);
    final noisyCalendar = applyLaplaceNoise(calendarEventsCreated);
    final noisyReminders = applyLaplaceNoise(remindersCreated);
    final noisyArchived = applyLaplaceNoise(archivedCount);

    if (existing != null) {
      await _db.dailyBriefDao.insertOrUpdate(existing.copyWith(
        notificationsReviewed: math.max(0, existing.notificationsReviewed + noisyReviewed),
        actionsCompleted: math.max(0, existing.actionsCompleted + noisyActions),
        calendarEventsCreated: math.max(0, existing.calendarEventsCreated + noisyCalendar),
        remindersCreated: math.max(0, existing.remindersCreated + noisyReminders),
        archivedCount: math.max(0, existing.archivedCount + noisyArchived),
      ));
    } else {
      await _db.dailyBriefDao.insertOrUpdate(DailyBriefEntry(
        id: 0,
        date: date,
        notificationsReviewed: noisyReviewed,
        actionsCompleted: noisyActions,
        calendarEventsCreated: noisyCalendar,
        remindersCreated: noisyReminders,
        archivedCount: noisyArchived,
      ));
    }
  }
}
