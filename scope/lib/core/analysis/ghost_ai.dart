import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/utils/timestamp_utils.dart';
import 'package:scope/core/utils/audit_logger.dart';

/// The result returned by the unified Ghost AI look-again inference model.
class GhostAIResult {
  /// The final score (0.0 to 1.0) after combining rules and overrides.
  final double reviewScore;

  /// Model prediction confidence (1.0 default for regression).
  final double? confidence;

  /// TFLite model inference execution time in microseconds.
  final int inferenceTimeUs;

  /// The 63-dimensional feature vector extracted from the notification.
  final List<double> featureVector;

  /// Raw prediction score (0.0 to 1.0) output by the TFLite model.
  final double predictedScore;

  /// Rule match score (0.0 to 1.0) output by the rule engine.
  final double? ruleScore;

  const GhostAIResult({
    required this.reviewScore,
    this.confidence,
    required this.inferenceTimeUs,
    required this.featureVector,
    required this.predictedScore,
    this.ruleScore,
  });
}

/// Core inference singleton coordinating look-again score predictions and overrides.
class GhostAI {
  static GhostAI? _instance;
  Interpreter? _interpreter;
  final RuleEngine _ruleEngine = RuleEngine();

  // Slide-cache for duplicate detection
  final List<AppNotification> _processedNotifications = [];
  static const int _maxCacheSize = 100;
  static const int _duplicateWindowMs = 300000; // 5 minutes

  GhostAI._();

  static GhostAI get instance => _instance ??= GhostAI._();

  /// Exposes rule engine compilation version.
  String get ruleVersion => _ruleEngine.version;

  /// Returns whether the model is loaded.
  bool get isModelLoaded => _interpreter != null;

  /// Initializes the TFLite interpreter and rules database once on startup.
  Future<void> initialize() async {
    if (_interpreter != null) return;
    try {
      // 1. Load interpreter from assets
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      debugPrint('GhostAI: TFLite interpreter loaded successfully.');
    } catch (e) {
      debugPrint('GhostAI: Failed to load TFLite model: $e');
    }

    try {
      // 2. Load and compile rules database
      final jsonStr = await rootBundle.loadString('assets/rules.json');
      _ruleEngine.compile(jsonStr);
      debugPrint('GhostAI: Rule engine initialized (version: ${_ruleEngine.version}).');
    } catch (e) {
      debugPrint('GhostAI: Failed to initialize rules database: $e');
    }
  }

  /// Public API: resolves look-again priority score for a notification.
  static Future<GhostAIResult> predict(
    AppNotification notification, {
    DateTime? now,
  }) async {
    return instance._predict(notification, now: now);
  }

  Future<GhostAIResult> _predict(
    AppNotification notification, {
    DateTime? now,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 1. Feature extraction using the existing FeatureExtractor
    final featureVector = FeatureExtractor.extractFromAppNotification(
      notification,
      now: now,
    );

    // 2. Model inference
    double predictedScore = 0.0;
    int inferenceTimeUs = 0;

    if (_interpreter != null) {
      final input = [featureVector];
      final output = List<double>.filled(1, 0.0).reshape([1, 1]);

      final inferStopwatch = Stopwatch()..start();
      _interpreter!.run(input, output);
      inferStopwatch.stop();

      inferenceTimeUs = inferStopwatch.elapsedMicroseconds;
      // Scale predicted score from 0.0-100.0 range to 0.0-1.0 range
      predictedScore = (output[0][0] / 100.0).clamp(0.0, 1.0);
    } else {
      // Heuristic fallback if model not loaded
      predictedScore = _heuristicLookAgainScore(featureVector);
    }

    // 3. Rule matching
    final ruleMatch = _ruleEngine.match(notification);
    double? ruleScore;
    if (ruleMatch != null) {
      switch (ruleMatch.priority) {
        case 'critical':
          ruleScore = 1.0;
          break;
        case 'high':
          ruleScore = 0.85;
          break;
        case 'medium':
          ruleScore = 0.50;
          break;
        case 'low':
        default:
          ruleScore = 0.15;
          break;
      }
    }

    // 4. Score Fusion (rules + predictions)
    double finalScore = predictedScore;
    if (ruleScore != null && ruleMatch != null) {
      // Immediate critical bypass triggers
      final isCriticalBypass = ruleMatch.priority == 'critical' ||
          ruleMatch.ruleId == 'otp_security' ||
          ruleMatch.ruleId == 'finance_debit' ||
          ruleMatch.ruleId == 'scholarship_portal';

      if (isCriticalBypass) {
        finalScore = 1.0;
      } else {
        // Average rule score and predicted score
        finalScore = (predictedScore + ruleScore) / 2.0;
      }
    }

    // 5. Apply deterministic overrides (expired OTP, expired reminders, duplicates, completed tasks)
    final hasOtp = featureVector[11] == 1.0; // contains_otp
    final hasDeadline = featureVector[27] == 1.0; // contains_deadline

    if (hasOtp && _isOtpExpired(notification, now: now)) {
      finalScore = 0.0;
    } else if (hasDeadline && _isReminderExpired(notification, now: now)) {
      finalScore = 0.0;
    } else if (_isDuplicate(notification)) {
      finalScore = 0.0;
    } else if (_isCompletedTask(notification)) {
      finalScore = 0.0;
    }

    stopwatch.stop();

    // Cache the notification for future duplicate checks
    _cacheNotification(notification);

    final result = GhostAIResult(
      reviewScore: finalScore,
      confidence: 1.0,
      inferenceTimeUs: inferenceTimeUs > 0 ? inferenceTimeUs : stopwatch.elapsedMicroseconds,
      featureVector: featureVector,
      predictedScore: predictedScore,
      ruleScore: ruleScore,
    );

    // Structured logging in debug mode
    if (kDebugMode) {
      _logStructured(notification, result);
    }

    return result;
  }

  /// Helper to compute heuristic score if model is not loaded.
  double _heuristicLookAgainScore(List<double> featureVector) {
    if (featureVector[11] == 1.0) return 1.0; // OTP
    if (featureVector[20] == 1.0) return 0.05; // Promo
    if (featureVector[10] == 1.0) return 0.85; // Money/finance
    if (featureVector[27] == 1.0) return 0.80; // Deadline
    return 0.35; // Default medium-low fallback
  }

  /// Parses Validity period of OTP and returns whether it is expired.
  bool _isOtpExpired(AppNotification notification, {DateTime? now}) {
    try {
      final lower = '${notification.title} ${notification.content}'.toLowerCase();
      final regex = RegExp(
        r'(?:valid|expires|active)\s+(?:for|in)?\s*(\d+)\s*(minute|minutes|min|mins|second|seconds|sec|secs)',
        caseSensitive: false,
      );
      final match = regex.firstMatch(lower);
      int durationMs = 600000; // Default 10 minutes

      if (match != null) {
        final amount = int.tryParse(match.group(1) ?? '');
        final unit = match.group(2)?.toLowerCase() ?? '';
        if (amount != null && amount > 0) {
          if (unit.startsWith('sec')) {
            durationMs = amount * 1000;
          } else {
            durationMs = amount * 60 * 1000;
          }
        }
      }

      final elapsedMs = TimestampUtils.getElapsedMs(notification.timestamp, now: now);
      final isExpired = elapsedMs > durationMs;

      ExpiryAuditLogger.instance.logExpiryEvaluation(
        notificationId: notification.id,
        type: 'OTP',
        isExpired: isExpired,
        reason: 'Elapsed: ${elapsedMs ~/ 1000}s, Duration: ${durationMs ~/ 1000}s',
      );

      return isExpired;
    } catch (e) {
      ExpiryAuditLogger.instance.logFallbackRecovery(
        notificationId: notification.id,
        component: 'GhostAI._isOtpExpired',
        error: e.toString(),
        fallbackAction: 'Assumed not expired',
      );
      return false;
    }
  }

  /// Checks if the notification is a candidate for relative reminder expiry logic.
  /// Prevents false-positive expiry evaluations on promotional, social, or general notifications.
  bool _isReminderCandidate(AppNotification notification, String combinedText) {
    final pkg = notification.packageName.toLowerCase();
    final cat = (notification.classifiedCategory ?? notification.category ?? '').toLowerCase();

    final isCalendarApp = pkg.contains('calendar') ||
        pkg.contains('reminder') ||
        pkg.contains('task') ||
        pkg.contains('todo') ||
        pkg.contains('keep') ||
        pkg.contains('jira') ||
        pkg.contains('clock') ||
        pkg.contains('alarm') ||
        pkg.contains('meet') ||
        pkg.contains('zoom') ||
        pkg.contains('teams');

    final isReminderCategory = cat == 'reminder' ||
        cat == 'event' ||
        cat == 'alarm' ||
        cat == 'task' ||
        cat == 'calendar' ||
        cat == 'work';

    final hasReminderKeywords = combinedText.contains('reminder') ||
        combinedText.contains('meeting') ||
        combinedText.contains('standup') ||
        combinedText.contains('appointment') ||
        combinedText.contains('schedule') ||
        combinedText.contains('deadline') ||
        combinedText.contains('due') ||
        combinedText.contains('starts in') ||
        combinedText.contains('begins in') ||
        combinedText.contains('valid until') ||
        combinedText.contains('expires in') ||
        combinedText.contains('payment due');

    final isPromo = cat == 'promotions' ||
        cat == 'promo' ||
        pkg.contains('promo') ||
        combinedText.contains('sale') ||
        combinedText.contains('discount') ||
        combinedText.contains('coupon') ||
        combinedText.contains('off on');

    if (isPromo && !hasReminderKeywords) {
      return false;
    }

    return isCalendarApp || isReminderCategory || hasReminderKeywords;
  }

  /// Parses Relative deadline from text and returns whether it has expired.
  bool _isReminderExpired(AppNotification notification, {DateTime? now}) {
    try {
      final lowerContent = notification.content.toLowerCase();
      final lowerTitle = notification.title.toLowerCase();
      final combined = '$lowerTitle $lowerContent';

      if (!_isReminderCandidate(notification, combined)) {
        return false;
      }

      final relativeRegex = RegExp(
        r'\bin\s+(\d{1,4})\s*(minute|minutes|min|mins|hour|hours|hr|hrs|day|days)\b',
        caseSensitive: false,
      );
      final match = relativeRegex.firstMatch(combined);

      if (match != null) {
        final amount = int.tryParse(match.group(1) ?? '');
        final unit = match.group(2)?.toLowerCase() ?? '';
        if (amount != null && amount > 0) {
          int durationMs = 0;
          if (unit.startsWith('min')) {
            durationMs = amount * 60 * 1000;
          } else if (unit.startsWith('hour') || unit.startsWith('hr')) {
            durationMs = amount * 60 * 60 * 1000;
          } else {
            durationMs = amount * 24 * 60 * 60 * 1000;
          }
          final elapsedMs = TimestampUtils.getElapsedMs(notification.timestamp, now: now);
          final isExpired = elapsedMs > durationMs;

          ExpiryAuditLogger.instance.logExpiryEvaluation(
            notificationId: notification.id,
            type: 'RelativeReminder',
            isExpired: isExpired,
            reason: 'Elapsed: ${elapsedMs ~/ 1000}s, Duration: ${durationMs ~/ 1000}s',
          );

          return isExpired;
        }
      }

      // Expiry check for calendar days (today/tonight in past)
      if (combined.contains('today') || combined.contains('tonight')) {
        final normMillis = TimestampUtils.normalizeToMillis(notification.timestamp, now: now);
        final notifDate = DateTime.fromMillisecondsSinceEpoch(normMillis);
        final referenceNow = now ?? DateTime.now();
        final isPastDay = notifDate.year < referenceNow.year ||
            (notifDate.year == referenceNow.year && notifDate.month < referenceNow.month) ||
            (notifDate.year == referenceNow.year && notifDate.month == referenceNow.month && notifDate.day < referenceNow.day);

        if (isPastDay) {
          ExpiryAuditLogger.instance.logExpiryEvaluation(
            notificationId: notification.id,
            type: 'CalendarDayReminder',
            isExpired: true,
            reason: 'Notif date (${notifDate.toIso8601String()}) is before now (${referenceNow.toIso8601String()})',
          );
          return true;
        }
      }

      return false;
    } catch (e) {
      ExpiryAuditLogger.instance.logFallbackRecovery(
        notificationId: notification.id,
        component: 'GhostAI._isReminderExpired',
        error: e.toString(),
        fallbackAction: 'Assumed not expired',
      );
      return false;
    }
  }

  /// Returns whether this notification is a duplicate within the sliding window.
  bool _isDuplicate(AppNotification notification) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Prune stale duplicates older than 5 minutes
    _processedNotifications.removeWhere((n) => now - n.timestamp > _duplicateWindowMs);

    for (final oldNotif in _processedNotifications) {
      if (oldNotif.packageName == notification.packageName &&
          oldNotif.title == notification.title &&
          oldNotif.content == notification.content &&
          oldNotif.id != notification.id) {
        return true;
      }
    }
    return false;
  }

  /// Caches the notification for duplicate checking.
  void _cacheNotification(AppNotification notification) {
    if (_processedNotifications.any((n) => n.id == notification.id)) return;
    _processedNotifications.add(notification);
    if (_processedNotifications.length > _maxCacheSize) {
      _processedNotifications.removeAt(0);
    }
  }

  /// Helper to clear the duplicate memory cache (used for unit tests).
  void clearCache() {
    _processedNotifications.clear();
  }

  /// Returns whether a notification indicates that a task/action is completed.
  bool _isCompletedTask(AppNotification notification) {
    final lowerContent = notification.content.toLowerCase();
    final lowerTitle = notification.title.toLowerCase();

    final completedRegex = RegExp(
      r'\b(completed|done|finished|resolved|successful|delivered|succeeded)\b',
      caseSensitive: false,
    );

    final isTaskApp = notification.packageName.contains('task') ||
        notification.packageName.contains('todo') ||
        notification.packageName.contains('jira') ||
        notification.packageName.contains('keep') ||
        notification.packageName.contains('calendar');

    final hasTaskKeywords = lowerTitle.contains('task') ||
        lowerTitle.contains('todo') ||
        lowerTitle.contains('reminder') ||
        lowerTitle.contains('payment') ||
        lowerTitle.contains('recharge') ||
        lowerTitle.contains('order');

    if (isTaskApp || hasTaskKeywords) {
      return completedRegex.hasMatch(lowerTitle) || completedRegex.hasMatch(lowerContent);
    }

    return false;
  }

  /// Outputs structured AI execution reports in debug mode.
  void _logStructured(AppNotification notification, GhostAIResult result) {
    debugPrint('=== GHOST AI INFERENCE REPORT ===');
    debugPrint('Notification: "${notification.title}" - "${notification.content}"');
    debugPrint('Package: ${notification.packageName}');
    debugPrint('Feature Vector (First 15): ${result.featureVector.take(15).toList()}...');
    debugPrint('Inference Time: ${result.inferenceTimeUs} us');
    debugPrint('Raw Predicted Score: ${(result.predictedScore * 100).toStringAsFixed(2)}');
    debugPrint('Rule Score: ${result.ruleScore != null ? (result.ruleScore! * 100).toStringAsFixed(2) : "N/A"}');
    debugPrint('Final Fused Score: ${(result.reviewScore * 100).toStringAsFixed(2)}');
    debugPrint('==================================');
  }
}
