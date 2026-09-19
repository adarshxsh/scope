import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/utils/smart_action_launcher.dart';
import 'package:scope/core/utils/smart_action_validator.dart';
import 'package:scope/core/utils/smart_actions.dart';

class MockNotificationBridge extends NotificationBridge {
  bool launchUrlResult = true;
  bool launchAppResult = true;
  String? lastLaunchedUrl;
  String? lastLaunchedApp;

  @override
  Future<bool> launchUrl(String url) async {
    lastLaunchedUrl = url;
    return launchUrlResult;
  }

  @override
  Future<bool> launchApp(String packageName) async {
    lastLaunchedApp = packageName;
    return launchAppResult;
  }
}

void main() {
  late MockNotificationBridge mockBridge;
  late SmartActionLauncherService launcher;

  setUp(() {
    SmartActionValidator.clearAuditLogs();
    mockBridge = MockNotificationBridge();
    launcher = SmartActionLauncherService(bridge: mockBridge);
  });

  final sampleNotification = AppNotification(
    id: 'n-100',
    packageName: 'com.example.app',
    title: 'Portal Link',
    content: 'Visit https://example.com/portal',
    timestamp: DateTime.now().millisecondsSinceEpoch,
    extractedFeatures: const {
      'urls': ['https://example.com/portal'],
    },
  );

  group('SmartActionLauncherService Launch Execution', () {
    test('launches valid URL action and logs audit entry', () async {
      final action = SmartAction(
        label: 'Open Portal',
        icon: Icons.language,
        type: SmartActionType.openUrl,
        url: 'https://example.com/portal',
      );

      final result = await launcher.launchAction(
        action: action,
        notification: sampleNotification,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isBlocked, isFalse);
      expect(mockBridge.lastLaunchedUrl, equals('https://example.com/portal'));
      expect(SmartActionValidator.auditLogs.isNotEmpty, isTrue);
      expect(SmartActionValidator.auditLogs.last.isAllowed, isTrue);
    });

    test('blocks malicious URL action and records blocked audit entry', () async {
      final action = SmartAction(
        label: 'Run Script',
        icon: Icons.code,
        type: SmartActionType.openUrl,
        url: 'javascript:alert(1)',
      );

      final result = await launcher.launchAction(
        action: action,
        notification: sampleNotification,
      );

      expect(result.isSuccess, isFalse);
      expect(result.isBlocked, isTrue);
      expect(mockBridge.lastLaunchedUrl, isNull);
      expect(SmartActionValidator.auditLogs.last.isAllowed, isFalse);
      expect(SmartActionValidator.auditLogs.last.status, equals(ValidationStatus.invalidScheme));
    });

    test('recovers gracefully with fallback result when URL launch fails', () async {
      mockBridge.launchUrlResult = false; // Simulates no browser app installed

      final action = SmartAction(
        label: 'Open Portal',
        icon: Icons.language,
        type: SmartActionType.openUrl,
        url: 'https://example.com/portal',
      );

      final result = await launcher.launchAction(
        action: action,
        notification: sampleNotification,
      );

      expect(result.isSuccess, isFalse);
      expect(result.isBlocked, isFalse);
      expect(result.fallbackReason, isNotNull);
      expect(result.message, contains('Unable to open link'));
    });

    test('launches target app intent when package name is valid', () async {
      final action = SmartAction(
        label: 'Pay',
        icon: Icons.payment,
        type: SmartActionType.pay,
        packageName: 'com.phonepe.app',
      );

      final result = await launcher.launchAction(
        action: action,
        notification: sampleNotification,
      );

      expect(result.isSuccess, isTrue);
      expect(mockBridge.lastLaunchedApp, equals('com.phonepe.app'));
    });

    test('recovers gracefully with fallback result when target app is not installed', () async {
      mockBridge.launchAppResult = false; // Target app not installed

      final action = SmartAction(
        label: 'Pay',
        icon: Icons.payment,
        type: SmartActionType.pay,
        packageName: 'com.uninstalled.app',
      );

      final result = await launcher.launchAction(
        action: action,
        notification: sampleNotification,
      );

      expect(result.isSuccess, isFalse);
      expect(result.isBlocked, isFalse);
      expect(result.fallbackReason, contains('not installed'));
    });
  });
}
