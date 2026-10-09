import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/screens/app_exclusion_screen.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late List<MethodCall> log;
  late NotificationBridge bridge;
  late NotificationController controller;

  setUp(() {
    channel = const MethodChannel('com.scope.notifications.test');
    log = [];
    bridge = NotificationBridge(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      if (call.method == 'getExcludedPackages') return <String>[];
      if (call.method == 'getExcludeSystemCategories') return false;
      if (call.method == 'setExcludedPackages') return true;
      if (call.method == 'setExcludeSystemCategories') return true;
      if (call.method == 'getInstalledApps') {
        return [
          {
            'packageName': 'com.chase.sig.android',
            'appName': 'Chase Mobile',
            'isSystemApp': false,
          },
          {
            'packageName': 'com.whatsapp',
            'appName': 'WhatsApp',
            'isSystemApp': false,
          },
        ];
      }
      return null;
    });

    controller = NotificationController(bridge: bridge);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    controller.dispose();
  });

  Widget buildSubject() {
    return MaterialApp(
      home: AppExclusionScreen(controller: controller),
    );
  }

  group('AppExclusionScreen Widget Tests', () {
    testWidgets('renders screen title and controls', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('App Exclusion Controls'), findsWidgets);
      expect(find.text('Exclude System Status & Media Notifications'), findsOneWidget);
      expect(find.text('Chase Mobile'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
    });

    testWidgets('toggles system categories filter', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(controller.excludeSystemCategories, false);

      final switchFinder = find.byType(Switch).first;
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(controller.excludeSystemCategories, true);
      expect(log.any((call) => call.method == 'setExcludeSystemCategories'), true);
    });

    testWidgets('toggles app exclusion status', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(controller.isPackageExcluded('com.chase.sig.android'), false);

      // Tap the switch next to Chase Mobile (second switch on screen)
      final appSwitchFinder = find.byType(Switch).at(1);
      await tester.tap(appSwitchFinder);
      await tester.pumpAndSettle();

      expect(controller.isPackageExcluded('com.chase.sig.android'), true);
      expect(log.any((call) => call.method == 'setExcludedPackages'), true);
    });

    testWidgets('filters app list when typing in search bar', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Chase');
      await tester.pumpAndSettle();

      expect(find.text('Chase Mobile'), findsOneWidget);
      expect(find.text('WhatsApp'), findsNothing);
    });
  });
}
