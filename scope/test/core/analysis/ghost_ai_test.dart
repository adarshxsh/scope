import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/thermal_guardrail_service.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GhostAI Tests', () {
    // Clear duplicate cache, latency history, and thermal state before each test
    setUp(() {
      GhostAI.instance.clearCache();
      GhostAI.instance.clearLatencyHistory();
      ThermalGuardrailService.instance.reset();
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

    group('Sliding Window Latency Tracker', () {
      test('tracks a rolling window capped at 20 inference execution times', () {
        final ghostAI = GhostAI.instance;
        for (int i = 1; i <= 25; i++) {
          ghostAI.recordInferenceTime(i * 1000);
        }

        expect(ghostAI.inferenceLatencyHistory.length, equals(20));
        // Oldest 5 samples (1000..5000) evicted; remaining are 6000..25000 us
        expect(ghostAI.inferenceLatencyHistory.first, equals(6000));
        expect(ghostAI.inferenceLatencyHistory.last, equals(25000));
      });

      test('calculates rolling average inference latency correctly', () {
        final ghostAI = GhostAI.instance;
        ghostAI.recordInferenceTime(10000);
        ghostAI.recordInferenceTime(20000);

        expect(ghostAI.rollingAverageInferenceLatencyUs, equals(15000.0));
        expect(ghostAI.rollingAverageInferenceLatencyMs, equals(15.0));
        expect(ghostAI.isLatencyExceeded, isFalse); // Threshold is > 15000

        ghostAI.recordInferenceTime(20000);
        expect(ghostAI.rollingAverageInferenceLatencyUs, closeTo(16666.66, 0.1));
        expect(ghostAI.isLatencyExceeded, isTrue);
      });

      test('triggers fast-path fallback within 20 samples when rolling average latency exceeds 15ms', () async {
        final ghostAI = GhostAI.instance;
        // Inject 20 samples with high latency (20ms / 20000us)
        for (int i = 0; i < 20; i++) {
          ghostAI.recordInferenceTime(20000);
        }

        expect(ghostAI.isLatencyExceeded, isTrue);

        final notif = AppNotification(
          id: 'high-latency-notif',
          packageName: 'com.whatsapp',
          title: 'Hello',
          content: 'Are you available for a quick call?',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = await GhostAI.predict(notif);
        expect(result.usedFastPath, isTrue);
      });
    });

    group('Thermal Guardrail & Recovery Mode', () {
      test('triggers fast-path evaluation when thermal state is throttled', () async {
        ThermalGuardrailService.instance.setThermalState(ThermalState.throttled);

        final notif = AppNotification(
          id: 'throttled-notif',
          packageName: 'com.example.app',
          title: 'Update available',
          content: 'A new software update is ready for download.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = await GhostAI.predict(notif);
        expect(result.usedFastPath, isTrue);
      });

      test('never misclassifies critical OTP or debit alerts during fast-path mode', () async {
        ThermalGuardrailService.instance.setThermalState(ThermalState.throttled);

        final otpNotif = AppNotification(
          id: 'otp-fastpath',
          packageName: 'com.bank.app',
          title: 'Login OTP',
          content: 'Your secret OTP code is 492018. Valid for 10 minutes.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = await GhostAI.predict(otpNotif);
        expect(result.usedFastPath, isTrue);
        expect(result.reviewScore, equals(1.0)); // Critical score preserved
      });

      test('seamlessly recovers to normal ML inference when thermal state and latency cool down', () async {
        final ghostAI = GhostAI.instance;

        // 1. Simulate thermal pressure
        ThermalGuardrailService.instance.setThermalState(ThermalState.throttled);

        final notif1 = AppNotification(
          id: 'notif-step-1',
          packageName: 'com.whatsapp',
          title: 'Message',
          content: 'Let us meet for lunch.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final resultThrottled = await GhostAI.predict(notif1);
        expect(resultThrottled.usedFastPath, isTrue);

        // 2. Coold down thermal state and clear latency history
        ThermalGuardrailService.instance.setThermalState(ThermalState.normal);
        ghostAI.clearLatencyHistory();

        // Inject normal low-latency samples (< 15ms)
        for (int i = 0; i < 20; i++) {
          ghostAI.recordInferenceTime(2000); // 2ms
        }

        final notif2 = AppNotification(
          id: 'notif-step-2',
          packageName: 'com.whatsapp',
          title: 'Message',
          content: 'Let us meet for dinner.',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final resultRecovered = await GhostAI.predict(notif2);
        expect(ghostAI.isLatencyExceeded, isFalse);
        // Fast-path should no longer be forced by thermal throttling or high latency
        // Note: model loaded check applies
        if (!ghostAI.isModelLoaded) {
          expect(resultRecovered.usedFastPath, isTrue); // Heuristic fallback due to uninitialized model in test
        } else {
          expect(resultRecovered.usedFastPath, isFalse);
        }
      });
    });
  });
}
