import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GhostAI Tests', () {
    // Clear duplicate cache before each test to prevent test cross-contamination
    setUp(() {
      GhostAI.instance.clearCache();
    });

    test('initialization handles missing assets and falls back gracefully', () async {
      // Should not throw, should log and proceed with isModelLoaded = false
      await GhostAI.instance.initialize();
      expect(GhostAI.instance.isModelLoaded, isFalse);
    });

    test('predict outputs basic inference results and falls back to heuristics', () async {
      final notif = AppNotification(
        id: 'otp-notif',
        packageName: 'com.whatsapp',
        title: 'WhatsApp Code',
        content: 'Your verification code is 882715. Valid for 10 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);

      expect(result.reviewScore, equals(1.0)); // OTP heuristic is 1.0 and not expired
      expect(result.confidence, equals(1.0));
      expect(result.inferenceTimeUs, isPositive);
      expect(result.featureVector, isNotEmpty);
      expect(result.featureVector.length, equals(63));
      expect(result.predictedScore, equals(1.0)); // Heuristic fallback score for OTP
    });

    group('Expired OTP Overrides', () {
      test('does not override fresh OTPs', () async {
        final freshNotif = AppNotification(
          id: 'otp-fresh',
          packageName: 'com.whatsapp',
          title: 'WhatsApp Code',
          content: 'Your verification code is 882715. Expires in 5 minutes.',
          timestamp: DateTime.now().millisecondsSinceEpoch - 60 * 1000, // 1 minute ago
        );

        final result = await GhostAI.predict(freshNotif);
        expect(result.reviewScore, equals(1.0)); // High priority
      });

      test('overrides expired OTP based on parsed expiry duration', () async {
        final expiredNotif = AppNotification(
          id: 'otp-expired',
          packageName: 'com.whatsapp',
          title: 'WhatsApp Code',
          content: 'Your verification code is 882715. Expires in 5 minutes.',
          timestamp: DateTime.now().millisecondsSinceEpoch - 6 * 60 * 1000, // 6 minutes ago
        );

        final result = await GhostAI.predict(expiredNotif);
        expect(result.reviewScore, equals(0.0)); // Overridden to 0
      });

      test('overrides expired OTP based on default duration (10 mins)', () async {
        final expiredNotifDefault = AppNotification(
          id: 'otp-expired-default',
          packageName: 'com.whatsapp',
          title: 'WhatsApp Code',
          content: 'Your verification code is 882715.',
          timestamp: DateTime.now().millisecondsSinceEpoch - 11 * 60 * 1000, // 11 minutes ago
        );

        final result = await GhostAI.predict(expiredNotifDefault);
        expect(result.reviewScore, equals(0.0)); // Overridden to 0
      });
    });

    group('Expired Reminder Overrides', () {
      test('does not override fresh reminders', () async {
        final freshReminder = AppNotification(
          id: 'reminder-fresh',
          packageName: 'com.google.android.calendar',
          title: 'Upcoming meeting reminder',
          content: 'Standup starts in 10 minutes',
          timestamp: DateTime.now().millisecondsSinceEpoch - 2 * 60 * 1000, // 2 minutes ago
        );

        final result = await GhostAI.predict(freshReminder);
        expect(result.reviewScore, equals(0.80)); // Heuristic deadline fallback
      });

      test('overrides expired relative reminders', () async {
        final expiredReminder = AppNotification(
          id: 'reminder-expired',
          packageName: 'com.google.android.calendar',
          title: 'Upcoming meeting reminder',
          content: 'Standup starts in 10 minutes',
          timestamp: DateTime.now().millisecondsSinceEpoch - 12 * 60 * 1000, // 12 minutes ago
        );

        final result = await GhostAI.predict(expiredReminder);
        expect(result.reviewScore, equals(0.0)); // Overridden to 0
      });

      test('overrides "today" reminders from a past calendar day', () async {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final expiredTodayReminder = AppNotification(
          id: 'reminder-expired-today',
          packageName: 'com.google.android.calendar',
          title: 'Task Due',
          content: 'Submit report today',
          timestamp: yesterday.millisecondsSinceEpoch,
        );

        final result = await GhostAI.predict(expiredTodayReminder);
        expect(result.reviewScore, equals(0.0)); // Overridden to 0
      });
    });

    group('Duplicate Notification Overrides', () {
      test('overrides duplicates within the sliding 5 minute window', () async {
        final firstNotif = AppNotification(
          id: 'notif-1',
          packageName: 'com.whatsapp',
          title: 'Mom',
          content: 'Please buy milk.',
          timestamp: DateTime.now().millisecondsSinceEpoch - 10 * 1000,
        );

        final duplicateNotif = AppNotification(
          id: 'notif-2', // Different ID
          packageName: 'com.whatsapp',
          title: 'Mom',
          content: 'Please buy milk.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final firstResult = await GhostAI.predict(firstNotif);
        final duplicateResult = await GhostAI.predict(duplicateNotif);

        expect(firstResult.reviewScore, isPositive);
        expect(duplicateResult.reviewScore, equals(0.0)); // Overridden to 0
      });

      test('does not override non-duplicate notifications', () async {
        final firstNotif = AppNotification(
          id: 'notif-1',
          packageName: 'com.whatsapp',
          title: 'Mom',
          content: 'Please buy milk.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final secondNotif = AppNotification(
          id: 'notif-2',
          packageName: 'com.whatsapp',
          title: 'Mom',
          content: 'Did you get the milk?', // Different content
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final firstResult = await GhostAI.predict(firstNotif);
        final secondResult = await GhostAI.predict(secondNotif);

        expect(firstResult.reviewScore, isPositive);
        expect(secondResult.reviewScore, isPositive); // Not overridden
      });

      test('does not override duplicates older than 5 minutes', () async {
        final oldNotif = AppNotification(
          id: 'notif-1',
          packageName: 'com.whatsapp',
          title: 'Mom',
          content: 'Please buy milk.',
          timestamp: DateTime.now().millisecondsSinceEpoch - 6 * 60 * 1000, // 6 minutes ago
        );

        final newNotif = AppNotification(
          id: 'notif-2',
          packageName: 'com.whatsapp',
          title: 'Mom',
          content: 'Please buy milk.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final oldResult = await GhostAI.predict(oldNotif);
        final newResult = await GhostAI.predict(newNotif);

        expect(oldResult.reviewScore, isPositive);
        expect(newResult.reviewScore, isPositive); // Not overridden because outside window
      });
    });

    group('Completed Task Overrides', () {
      test('overrides completed tasks from task apps', () async {
        final completedTask = AppNotification(
          id: 'task-done',
          packageName: 'com.todoist',
          title: 'Project Alpha',
          content: 'Task completed successfully',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = await GhostAI.predict(completedTask);
        expect(result.reviewScore, equals(0.0)); // Overridden to 0
      });

      test('overrides tasks with completion keywords in title', () async {
        final completedTaskTitle = AppNotification(
          id: 'task-done-title',
          packageName: 'com.example.app',
          title: 'Task Done',
          content: 'Finished work',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = await GhostAI.predict(completedTaskTitle);
        expect(result.reviewScore, equals(0.0)); // Overridden to 0
      });

      test('does not override active tasks', () async {
        final activeTask = AppNotification(
          id: 'task-active',
          packageName: 'com.todoist',
          title: 'Project Alpha',
          content: 'Buy groceries',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = await GhostAI.predict(activeTask);
        expect(result.reviewScore, isPositive); // Not overridden
      });
    });

    group('Prediction Cache Tests', () {
      test('bypasses redundant model inference on cached predictions', () async {
        final notif = AppNotification(
          id: 'cache-test-1',
          packageName: 'com.example.news',
          title: 'Breaking News',
          content: 'Major announcement today in technology.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        // First prediction -> Cache Miss
        final firstResult = await GhostAI.predict(notif);
        expect(GhostAI.instance.cacheMisses, isPositive);
        final initialHits = GhostAI.instance.cacheHits;

        // Second prediction for identical notification -> Cache Hit
        final secondResult = await GhostAI.predict(notif);
        expect(GhostAI.instance.cacheHits, equals(initialHits + 1));
        expect(secondResult.reviewScore, equals(firstResult.reviewScore));
        expect(secondResult.inferenceTimeUs, equals(0)); // 0us indicates inference was bypassed
      });

      test('dynamic overrides evaluate correctly on cached predictions', () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final otpNotif = AppNotification(
          id: 'otp-cache-test',
          packageName: 'com.bank.app',
          title: 'Bank OTP',
          content: 'Your OTP code is 492011. Valid for 5 minutes.',
          timestamp: now,
        );

        // First call caches the raw prediction (fresh OTP)
        final firstResult = await GhostAI.predict(otpNotif);
        expect(firstResult.reviewScore, equals(1.0));

        // Create notification with same ID/content but timestamp set to 10 minutes ago
        final expiredOtpNotif = AppNotification(
          id: 'otp-cache-test',
          packageName: 'com.bank.app',
          title: 'Bank OTP',
          content: 'Your OTP code is 492011. Valid for 5 minutes.',
          timestamp: now - 10 * 60 * 1000,
        );

        // This will miss cache key because timestamp differs, but let's test prediction override
        final secondResult = await GhostAI.predict(expiredOtpNotif);
        expect(secondResult.reviewScore, equals(0.0));
      });

      test('clearCache resets prediction cache and performance metrics', () async {
        final notif = AppNotification(
          id: 'clear-cache-test',
          packageName: 'com.example.app',
          title: 'Test Title',
          content: 'Test Content',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        await GhostAI.predict(notif);
        expect(GhostAI.instance.predictionCacheSize, equals(1));

        GhostAI.instance.clearCache();
        expect(GhostAI.instance.predictionCacheSize, equals(0));
        expect(GhostAI.instance.cacheHits, equals(0));
        expect(GhostAI.instance.cacheMisses, equals(0));
      });
    });
  });
}
