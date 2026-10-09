import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/resource_state_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Thermal and Battery Dynamic Fallback Integration Tests', () {
    late ResourceStateController resourceController;
    late GhostAnalysisEngine engine;

    setUp(() async {
      resourceController = ResourceStateController();
      resourceController.reset();
      engine = GhostAnalysisEngine(resourceController: resourceController);
      await engine.initialize();
    });

    tearDown(() {
      resourceController.reset();
      GhostAI.instance.clearCache();
    });

    test('bypasses TFLite model execution and updates metadata under severe thermal state', () async {
      resourceController.updateResourceState(thermalStatus: 3); // Severe thermal state

      final notification = AppNotification(
        id: 'test_thermal_1',
        packageName: 'com.whatsapp',
        title: 'New message',
        content: 'Hey, are you free for a call?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Warm-up call to avoid cold asset I/O overhead
      await engine.analyze(notification);

      final result = await engine.analyze(notification);

      expect(result.engineVersion, '2.0.0-hybrid (thermal-fallback)');
      expect(result.modelVersion, 'thermal-save-heuristic-fallback');
      expect(result.explanation, contains('Thermal/Battery guardrail active'));
      expect(result.latencyMs, lessThan(10));
    });

    test('bypasses TFLite model execution and updates metadata under low battery (<15%)', () async {
      resourceController.updateResourceState(batteryLevel: 10); // 10% battery

      final notification = AppNotification(
        id: 'test_battery_1',
        packageName: 'com.google.android.gm',
        title: 'Weekly Digest',
        content: 'Check out the top updates from last week',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await engine.analyze(notification);

      expect(result.engineVersion, '2.0.0-hybrid (thermal-fallback)');
      expect(result.modelVersion, 'thermal-save-heuristic-fallback');
      expect(result.priority, isNotNull);
    });

    test('preserves deterministic security rules and OTP classification during thermal bypass', () async {
      resourceController.updateResourceState(thermalStatus: 4); // Critical thermal state

      final otpNotification = AppNotification(
        id: 'test_otp_security',
        packageName: 'com.whatsapp',
        title: 'Verification code',
        content: 'Your OTP code is 987654. Valid for 10 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await engine.analyze(otpNotification);

      expect(result.engineVersion, '2.0.0-hybrid (thermal-fallback)');
      expect(result.priority, 'critical');
      expect(result.priorityScore, 1.0);
    });

    test('preserves OTP expiration checks during thermal bypass', () async {
      resourceController.updateResourceState(thermalStatus: 3); // Severe thermal state

      final oldTimestamp = DateTime.now().millisecondsSinceEpoch - (15 * 60 * 1000); // 15 mins ago
      final expiredOtp = AppNotification(
        id: 'test_expired_otp',
        packageName: 'com.whatsapp',
        title: 'Verification code',
        content: 'Your OTP code is 123456. Valid for 5 minutes.',
        timestamp: oldTimestamp,
      );

      final result = await engine.analyze(expiredOtp);

      expect(result.engineVersion, '2.0.0-hybrid (thermal-fallback)');
      expect(result.priorityScore, 0.0);
    });

    test('runs standard ML hybrid pipeline when device resource state is normal', () async {
      resourceController.reset(); // Normal thermal and battery state

      final notification = AppNotification(
        id: 'test_normal_1',
        packageName: 'com.whatsapp',
        title: 'Hello',
        content: 'Meeting in 5 minutes',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await engine.analyze(notification);

      expect(result.engineVersion, isNot(contains('(thermal-fallback)')));
    });
  });
}
