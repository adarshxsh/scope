import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/utils/smart_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationBridge bridge;
  late MethodChannel channel;
  late List<MethodCall> channelLog;
  late ProviderContainer container;
  late NotificationController controller;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications.test');
    bridge = NotificationBridge(channel: channel);
    channelLog = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      channelLog.add(call);
      if (call.method == 'launchUrl') {
        return true;
      }
      if (call.method == 'launchApp') {
        return true;
      }
      return null;
    });

    container = ProviderContainer();
    controller = NotificationController(
      bridge: bridge,
      storage: InMemoryNotificationStorage(),
      container: container,
    );
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NotificationBridge Launcher Methods', () {
    test('launchUrl invokes launchUrl on method channel', () async {
      final success = await bridge.launchUrl('https://example.com');
      expect(success, isTrue);
      expect(channelLog.single.method, equals('launchUrl'));
      expect(channelLog.single.arguments, equals({'url': 'https://example.com'}));
    });

    test('launchApp invokes launchApp on method channel', () async {
      final success = await bridge.launchApp('com.example.app');
      expect(success, isTrue);
      expect(channelLog.single.method, equals('launchApp'));
      expect(channelLog.single.arguments, equals({'packageName': 'com.example.app'}));
    });
  });

  group('NotificationController.executeSmartAction', () {
    test('executes valid openUrl action via launchUrl and increments actionsCompleted', () async {
      final notification = AppNotification(
        id: 'n1',
        packageName: 'com.browser.app',
        title: 'New Portal',
        content: 'Visit https://portal.scope.dev',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: {
          'urls': ['https://portal.scope.dev'],
        },
      );

      const action = SmartAction(
        label: 'Open Portal',
        icon: Icons.language,
        type: SmartActionType.openUrl,
        url: 'https://portal.scope.dev',
      );

      final result = await controller.executeSmartAction(action, notification);

      expect(result.success, isTrue);
      expect(result.wasBlocked, isFalse);
      expect(controller.sessionStats.actionsCompleted, equals(1));
      expect(channelLog.any((c) => c.method == 'launchUrl'), isTrue);
    });

    test('blocks dangerous file URL action and increments blockedActionsCount telemetry', () async {
      final notification = AppNotification(
        id: 'n2',
        packageName: 'com.malicious.app',
        title: 'Security Alert',
        content: 'Check file',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      const action = SmartAction(
        label: 'Open File',
        icon: Icons.language,
        type: SmartActionType.openUrl,
        url: 'file:///etc/passwd',
      );

      final result = await controller.executeSmartAction(action, notification);

      expect(result.success, isFalse);
      expect(result.wasBlocked, isTrue);
      expect(result.error, contains('blocked'));
      expect(controller.sessionStats.blockedActionsCount, equals(1));
      expect(channelLog.where((c) => c.method == 'launchUrl'), isEmpty);
    });

    test('falls back to launchApp when action URL is missing', () async {
      final notification = AppNotification(
        id: 'n3',
        packageName: 'com.finance.app',
        title: 'Bill Due',
        content: 'Payment due for ₹500',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      const action = SmartAction(
        label: 'Pay',
        icon: Icons.payment,
        type: SmartActionType.pay,
        packageName: 'com.finance.app',
      );

      final result = await controller.executeSmartAction(action, notification);

      expect(result.success, isTrue);
      expect(controller.sessionStats.actionsCompleted, equals(1));
      expect(channelLog.any((c) => c.method == 'launchApp'), isTrue);
    });

    test('executes archive and complete actions correctly', () async {
      final notification = AppNotification(
        id: 'n4',
        packageName: 'com.test.app',
        title: 'Task',
        content: 'Review document',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      container.read(reviewQueueProvider.notifier).add(notification);

      const archiveAction = SmartAction(
        label: 'Archive',
        icon: Icons.archive,
        type: SmartActionType.archive,
      );

      final archiveRes = await controller.executeSmartAction(archiveAction, notification);
      expect(archiveRes.success, isTrue);
      expect(controller.isArchived('n4'), isTrue);
    });
  });
}
