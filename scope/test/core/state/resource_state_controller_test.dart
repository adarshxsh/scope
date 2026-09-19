import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/state/resource_state_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ResourceStateController Tests', () {
    late ResourceStateController controller;

    setUp(() {
      controller = ResourceStateController();
      controller.reset();
    });

    tearDown(() {
      controller.reset();
    });

    test('defaults to normal state and unconstrained execution policy', () {
      expect(controller.thermalStatus, 0);
      expect(controller.batteryLevel, 100);
      expect(controller.isCharging, false);
      expect(controller.executionPolicy, ExecutionPolicy.normal);
      expect(controller.shouldBypassTFLite, false);
    });

    test('maps severe thermal status (3) to critical execution policy', () {
      controller.updateResourceState(thermalStatus: 3);
      expect(controller.executionPolicy, ExecutionPolicy.critical);
      expect(controller.shouldBypassTFLite, true);
    });

    test('maps critical thermal status (4) to critical execution policy', () {
      controller.updateResourceState(thermalStatus: 4);
      expect(controller.executionPolicy, ExecutionPolicy.critical);
      expect(controller.shouldBypassTFLite, true);
    });

    test('maps moderate thermal status (2) to degraded execution policy', () {
      controller.updateResourceState(thermalStatus: 2);
      expect(controller.executionPolicy, ExecutionPolicy.degraded);
      expect(controller.shouldBypassTFLite, true);
    });

    test('maps low battery level (<15%) to critical execution policy', () {
      controller.updateResourceState(batteryLevel: 10);
      expect(controller.executionPolicy, ExecutionPolicy.critical);
      expect(controller.shouldBypassTFLite, true);
    });

    test('maps battery level between 15% and 20% to degraded execution policy', () {
      controller.updateResourceState(batteryLevel: 18);
      expect(controller.executionPolicy, ExecutionPolicy.degraded);
      expect(controller.shouldBypassTFLite, true);
    });

    test('manual policy override takes precedence over raw signals', () {
      controller.updateResourceState(
        thermalStatus: 0,
        batteryLevel: 100,
        policyOverride: ExecutionPolicy.critical,
      );
      expect(controller.executionPolicy, ExecutionPolicy.critical);
      expect(controller.shouldBypassTFLite, true);
    });

    test('reset clears policy overrides and restores default signals', () {
      controller.updateResourceState(
        thermalStatus: 4,
        batteryLevel: 5,
        policyOverride: ExecutionPolicy.critical,
      );
      controller.reset();
      expect(controller.thermalStatus, 0);
      expect(controller.batteryLevel, 100);
      expect(controller.executionPolicy, ExecutionPolicy.normal);
      expect(controller.shouldBypassTFLite, false);
    });
  });
}
