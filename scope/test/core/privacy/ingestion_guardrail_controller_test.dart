import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/privacy/ingestion_guardrail_controller.dart';

class MockNotificationBridge extends NotificationBridge {
  Map<String, dynamic>? lastSyncedPolicy;

  @override
  Future<bool> syncIngestionPolicy(Map<String, dynamic> policy) async {
    lastSyncedPolicy = policy;
    return true;
  }
}

void main() {
  group('IngestionGuardrailController Tests', () {
    late IngestionGuardrailController controller;

    setUp(() {
      controller = IngestionGuardrailController();
    });

    test('Initializes with default policy', () {
      expect(controller.policy.blacklistedPackages, contains('com.android.systemui'));
      expect(controller.policy.isWhitelistingEnabled, isFalse);
    });

    test('Mutates blacklisted packages', () {
      controller.addBlacklistedPackage('com.spam.app');
      expect(controller.policy.blacklistedPackages, contains('com.spam.app'));

      controller.removeBlacklistedPackage('com.spam.app');
      expect(controller.policy.blacklistedPackages, isNot(contains('com.spam.app')));
    });

    test('Mutates excluded categories and whitelisting toggle', () {
      controller.addExcludedCategory('gaming');
      expect(controller.policy.excludedCategories, contains('gaming'));

      controller.setWhitelistingEnabled(true);
      expect(controller.policy.isWhitelistingEnabled, isTrue);

      controller.addWhitelistedPackage('com.trusted.app');
      expect(controller.policy.whitelistedPackages, contains('com.trusted.app'));
    });

    test('Syncs policy to native bridge', () async {
      final mockBridge = MockNotificationBridge();
      controller.addBlacklistedPackage('com.bad.app');

      final success = await controller.syncToNative(mockBridge);
      expect(success, isTrue);
      expect(mockBridge.lastSyncedPolicy, isNotNull);
      expect((mockBridge.lastSyncedPolicy!['blacklistedPackages'] as List), contains('com.bad.app'));
    });
  });
}
