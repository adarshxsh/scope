import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/audit_logger.dart';
import 'package:scope/core/utils/timestamp_utils.dart';

void main() {
  group('TimestampUtils Unit Tests', () {
    final now = DateTime(2026, 6, 20, 12, 0, 0); // Reference time

    test('normalizes 10-digit unix seconds timestamps to milliseconds', () {
      final secondsTimestamp = 1700000000; // 10 digits
      final normalized = TimestampUtils.normalizeToMillis(secondsTimestamp, now: now);
      expect(normalized, equals(1700000000000));
    });

    test('preserves 13-digit milliseconds timestamps', () {
      final millisTimestamp = 1700000000000; // 13 digits
      final normalized = TimestampUtils.normalizeToMillis(millisTimestamp, now: now);
      expect(normalized, equals(1700000000000));
    });

    test('normalizes 16-digit microseconds timestamps to milliseconds', () {
      final microsTimestamp = 1700000000000000; // 16 digits
      final normalized = TimestampUtils.normalizeToMillis(microsTimestamp, now: now);
      expect(normalized, equals(1700000000000));
    });

    test('handles zero and negative timestamps gracefully by returning reference now', () {
      final zeroNormalized = TimestampUtils.normalizeToMillis(0, now: now);
      expect(zeroNormalized, equals(now.millisecondsSinceEpoch));

      final negNormalized = TimestampUtils.normalizeToMillis(-100, now: now);
      expect(negNormalized, equals(now.millisecondsSinceEpoch));
    });

    test('clamps future timestamps exceeding 1 day skew to current time', () {
      final futureTimestamp = now.millisecondsSinceEpoch + 100000000; // > 86400000 ms
      final clamped = TimestampUtils.normalizeToMillis(futureTimestamp, now: now);
      expect(clamped, equals(now.millisecondsSinceEpoch));
    });

    test('calculates safe elapsed time without negative values', () {
      final pastTimestamp = now.millisecondsSinceEpoch - 300000; // 5 minutes ago
      final elapsed = TimestampUtils.getElapsedMs(pastTimestamp, now: now);
      expect(elapsed, equals(300000));

      final zeroElapsed = TimestampUtils.getElapsedMs(0, now: now);
      expect(zeroElapsed, equals(0));
    });
  });

  group('ExpiryAuditLogger Unit Tests', () {
    setUp(() {
      ExpiryAuditLogger.instance.clear();
    });

    test('redacts email, phone, OTP, and financial amounts from audit logs', () {
      final sensitiveMessage =
          'User user@example.com with phone +15551234567 used OTP 882715 for ₹5000 transfer';
      final redacted = ExpiryAuditLogger.redactPii(sensitiveMessage);

      expect(redacted, contains('[EMAIL_REDACTED]'));
      expect(redacted, contains('[PHONE_REDACTED]'));
      expect(redacted, contains('[OTP_REDACTED]'));
      expect(redacted, contains('[AMOUNT_REDACTED]'));
      expect(redacted, isNot(contains('user@example.com')));
      expect(redacted, isNot(contains('+15551234567')));
    });

    test('maintains bounded buffer capacity of 100 entries', () {
      for (int i = 0; i < 120; i++) {
        ExpiryAuditLogger.instance.log(
          level: AuditLogLevel.info,
          category: 'Test',
          message: 'Log entry $i',
        );
      }

      final logs = ExpiryAuditLogger.instance.logs;
      expect(logs.length, equals(100));
      expect(logs.first.message, equals('Log entry 20'));
      expect(logs.last.message, equals('Log entry 119'));
    });
  });

  group('Timestamp Expiry Evaluation & Guardrail Tests', () {
    final referenceNow = DateTime(2026, 6, 20, 12, 0, 0);

    setUp(() {
      ExpiryAuditLogger.instance.clear();
    });

    test('validates timestamp in seconds and prevents false expiry score corruption', () async {
      // Notification timestamp given in seconds (10 digits) created 2 minutes before referenceNow
      final secondsTs = (referenceNow.millisecondsSinceEpoch - 120000) ~/ 1000;

      final notif = AppNotification(
        id: 'otp-seconds-ts',
        packageName: 'com.whatsapp',
        title: 'Verification Code',
        content: 'Your code is 492810. Valid for 10 minutes.',
        timestamp: secondsTs,
      );

      final result = await GhostAI.predict(notif, now: referenceNow);

      // Should NOT be expired because 2 mins elapsed < 10 mins duration
      expect(result.reviewScore, equals(1.0));
      expect(ExpiryAuditLogger.instance.logs, isNotEmpty);
    });

    test('prevents false-positive expiry on non-reminder promotional messages', () async {
      // Promo message containing "in 3 days"
      final promoNotif = AppNotification(
        id: 'promo-in-3-days',
        packageName: 'com.amazon.shopping',
        title: 'Mega Offer',
        content: 'Get 50% discount in 3 days during huge sale!',
        timestamp: referenceNow.millisecondsSinceEpoch - (4 * 86400000), // 4 days ago
        category: 'Promotions',
      );

      final result = await GhostAI.predict(promoNotif, now: referenceNow);

      // Should NOT be overridden to 0.0 by reminder expiry logic
      expect(result.reviewScore, greaterThan(0.0));
    });

    test('correctly expires relative meeting reminders after deadline elapses', () async {
      final meetingNotif = AppNotification(
        id: 'meeting-15m',
        packageName: 'com.google.android.calendar',
        title: 'Calendar Reminder',
        content: 'Team standup meeting in 15 minutes',
        timestamp: referenceNow.millisecondsSinceEpoch - (20 * 60000), // 20 mins ago
        category: 'Reminder',
      );

      final result = await GhostAI.predict(meetingNotif, now: referenceNow);

      // 20 mins elapsed > 15 mins duration -> Expired (0.0)
      expect(result.reviewScore, equals(0.0));
    });

    test('FeatureExtractor calculates dynamic remaining deadline minutes', () {
      final timestampMillis = referenceNow.millisecondsSinceEpoch - (5 * 60000); // 5 mins ago

      final input = NotificationFeatureInput(
        appName: 'Calendar',
        packageName: 'com.google.calendar',
        title: 'Meeting',
        body: 'Sync starts in 15 minutes',
        timestampMillis: timestampMillis,
      );

      final vector = FeatureExtractor.extractVector(input, now: referenceNow);
      // Feature 49 (deadline_minutes_remaining) should be 15 - 5 = 10 minutes
      final remainingMinutes = vector.values[49];
      expect(remainingMinutes, equals(10.0));
    });
  });
}
