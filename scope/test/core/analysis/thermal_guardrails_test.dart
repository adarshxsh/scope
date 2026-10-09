import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/analysis/thermal_guardrails.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ThermalGuardrails.resetInstance();
  });

  group('ThermalGuardrails Unit Tests', () {
    test('Default state is normal with full ML execution strategy', () {
      final guardrails = ThermalGuardrails.instance;
      expect(guardrails.thermalState, ThermalState.normal);
      expect(guardrails.batteryLevel, 1.0);
      expect(guardrails.isLowPowerMode, false);
      expect(guardrails.shouldUseFastPath, false);
      expect(guardrails.activeStrategy, ExecutionStrategy.fullMl);
    });

    test('Engages fast-path fallback on serious or critical thermal state', () {
      final guardrails = ThermalGuardrails.instance;

      guardrails.updateThermalState(ThermalState.fair);
      expect(guardrails.shouldUseFastPath, false);

      guardrails.updateThermalState(ThermalState.serious);
      expect(guardrails.shouldUseFastPath, true);
      expect(guardrails.activeStrategy, ExecutionStrategy.fastPathFallback);

      guardrails.updateThermalState(ThermalState.critical);
      expect(guardrails.shouldUseFastPath, true);
    });

    test('Engages fast-path fallback on low battery (< 15%) or low power mode', () {
      final guardrails = ThermalGuardrails.instance;

      guardrails.updateBatteryState(batteryLevel: 0.20, isLowPowerMode: false);
      expect(guardrails.shouldUseFastPath, false);

      guardrails.updateBatteryState(batteryLevel: 0.10, isLowPowerMode: false);
      expect(guardrails.shouldUseFastPath, true);

      guardrails.updateBatteryState(batteryLevel: 0.50, isLowPowerMode: true);
      expect(guardrails.shouldUseFastPath, true);
    });

    test('Engages fast-path fallback when rolling average latency exceeds 50ms', () {
      final guardrails = ThermalGuardrails.instance;

      for (int i = 0; i < 5; i++) {
        guardrails.recordLatency(30);
      }
      expect(guardrails.rollingAverageLatencyMs, 30.0);
      expect(guardrails.shouldUseFastPath, false);

      for (int i = 0; i < 5; i++) {
        guardrails.recordLatency(80);
      }
      // Rolling average = (5*30 + 5*80) / 10 = 55ms > 50ms threshold
      expect(guardrails.rollingAverageLatencyMs, 55.0);
      expect(guardrails.shouldUseFastPath, true);
    });

    test('Sanitizes PII data correctly and redacts cleartext sensitive values', () {
      const text = 'OTP code 883102 sent to test@example.com / +1 555-123-4567. Charged Rs 1500 on card 4111 2222 3333 4444.';
      final sanitized = ThermalGuardrails.sanitizePii(text);

      expect(sanitized, contains('[REDACTED_CODE]'));
      expect(sanitized, contains('[REDACTED_EMAIL]'));
      expect(sanitized, contains('[REDACTED_PHONE]'));
      expect(sanitized, contains('[REDACTED_AMOUNT]'));
      expect(sanitized, contains('[REDACTED_CARD]'));

      expect(sanitized, isNot(contains('883102')));
      expect(sanitized, isNot(contains('test@example.com')));
      expect(sanitized, isNot(contains('555-123-4567')));
      expect(sanitized, isNot(contains('1500')));
    });
  });

  group('GhostAnalysisEngine Dynamic Fallback Tests', () {
    late GhostAnalysisEngine engine;

    setUp(() async {
      ThermalGuardrails.resetInstance();
      engine = GhostAnalysisEngine();
      await engine.initialize();
    });

    test('Executes fast-path fallback under elevated thermal pressure with sub-50ms latency', () async {
      ThermalGuardrails.instance.updateThermalState(ThermalState.serious);

      const notif = AppNotification(
        id: 'thermal_test_1',
        packageName: 'com.whatsapp',
        title: 'Bank Alert',
        content: 'Your account was debited Rs. 2500. Use code 991823 for verification.',
        timestamp: 1600000000000,
      );

      final result = await engine.analyze(notif);

      expect(result.modelVersion, 'fast-path-fallback');
      expect(result.explanation, contains('Fast-path thermal/resource fallback engaged'));
      expect(result.latencyMs, lessThan(50));
      expect(result.priority, isNotNull);
    });

    test('Executes full ML path when thermal state is normal', () async {
      ThermalGuardrails.instance.updateThermalState(ThermalState.normal);

      const notif = AppNotification(
        id: 'thermal_test_2',
        packageName: 'com.whatsapp',
        title: 'Meeting Notice',
        content: 'Standup starts in 10 minutes',
        timestamp: 1600000000000,
      );

      final result = await engine.analyze(notif);

      expect(result.modelVersion, isNot('fast-path-fallback'));
    });
  });

  group('Input Validation and Memory Growth Bounds Tests', () {
    test('AppNotification.fromMap truncates over-sized inputs to safe character limits', () {
      final hugeTitle = 'A' * 1000;
      final hugeContent = 'B' * 5000;

      final map = {
        'id': 'test_huge_1',
        'packageName': 'com.example.huge',
        'title': hugeTitle,
        'content': hugeContent,
        'timestamp': 1600000000000,
      };

      final notif = AppNotification.fromMap(map);

      expect(notif.title.length, 500);
      expect(notif.content.length, 2000);
    });

    test('ReviewQueueNotifier caps in-memory queue at 500 items maximum', () {
      final notifier = ReviewQueueNotifier();

      final list = List.generate(
        600,
        (i) => AppNotification(
          id: 'notif_$i',
          packageName: 'com.example.app$i',
          title: 'Title $i',
          content: 'Content $i',
          timestamp: 1600000000000 + i,
        ),
      );

      notifier.load(list);

      expect(notifier.currentList.length, 500);
    });
  });
}
