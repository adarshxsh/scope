import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/thermal_guardrail_service.dart';

void main() {
  group('ThermalGuardrailService Tests', () {
    late ThermalGuardrailService service;

    setUp(() {
      service = ThermalGuardrailService.instance;
      service.reset();
    });

    test('initial state defaults to normal execution', () {
      expect(service.thermalState, equals(ThermalState.normal));
      expect(service.batteryLevel, equals(1.0));
      expect(service.isCharging, isFalse);
      expect(service.isLowPowerMode, isFalse);
      expect(service.isNormal, isTrue);
      expect(service.isWarm, isFalse);
      expect(service.isThrottled, isFalse);
    });

    test('setThermalState updates state correctly', () {
      service.setThermalState(ThermalState.warm);
      expect(service.thermalState, equals(ThermalState.warm));
      expect(service.isWarm, isTrue);
      expect(service.isThrottled, isFalse);

      service.setThermalState(ThermalState.throttled);
      expect(service.thermalState, equals(ThermalState.throttled));
      expect(service.isThrottled, isTrue);
    });

    test('updateBatteryState triggers throttled status on low battery when uncharging', () {
      service.updateBatteryState(batteryLevel: 0.10, isCharging: false);
      expect(service.isThrottled, isTrue);

      // Charging on low battery removes low-battery throttle
      service.updateBatteryState(batteryLevel: 0.10, isCharging: true);
      expect(service.isThrottled, isFalse);
    });

    test('low power mode triggers throttled status', () {
      service.setLowPowerMode(true);
      expect(service.isThrottled, isTrue);

      service.setLowPowerMode(false);
      expect(service.isThrottled, isFalse);
    });

    test('reset restores default state', () {
      service.setThermalState(ThermalState.throttled);
      service.updateBatteryState(batteryLevel: 0.05, isCharging: false, isLowPowerMode: true);
      expect(service.isThrottled, isTrue);

      service.reset();
      expect(service.thermalState, equals(ThermalState.normal));
      expect(service.batteryLevel, equals(1.0));
      expect(service.isThrottled, isFalse);
    });
  });
}
