import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/privacy/privacy_engine.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/screens/notification_privacy_screen.dart';

class MockNotificationBridge extends NotificationBridge {
  List<String> mockBlacklist = [];
  List<String> mockCategoryRules = [];

  @override
  Future<bool> isListenerEnabled() async => true;

  @override
  Future<List<String>> getPackageExclusionList() async => mockBlacklist;

  @override
  Future<List<String>> getCategoryExclusionRules() async => mockCategoryRules;

  @override
  Future<bool> setPackageExclusionList(List<String> packages) async {
    mockBlacklist = List.from(packages);
    return true;
  }

  @override
  Future<bool> setCategoryExclusionRules(List<String> categories) async {
    mockCategoryRules = List.from(categories);
    return true;
  }

  @override
  Future<List<Map<String, String>>> getInstalledApps() async {
    return [
      {'appName': 'Signal', 'packageName': 'org.thoughtcrime.securesms'},
      {'appName': 'Telegram', 'packageName': 'org.telegram.messenger'},
      {'appName': 'WhatsApp', 'packageName': 'com.whatsapp'},
    ];
  }
}

void main() {
  group('NotificationPrivacyScreen Widget Tests', () {
    late MockNotificationBridge mockBridge;
    late NotificationController controller;

    setUp(() {
      mockBridge = MockNotificationBridge();
      controller = NotificationController(
        bridge: mockBridge,
        storage: InMemoryNotificationStorage(),
        privacyEngine: PrivacyEngine(),
      );
    });

    testWidgets('renders category toggles and installed apps list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPrivacyScreen(controller: controller),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Ingestion Guardrails'), findsOneWidget);
      expect(find.text('Exclude Sensitive Categories (OTPs & Health)'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, 'Signal'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, 'Telegram'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, 'WhatsApp'), findsOneWidget);
    });

    testWidgets('toggles sensitive category exclusions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPrivacyScreen(controller: controller),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      final switchFinder = find.widgetWithText(SwitchListTile, 'Exclude Sensitive Categories (OTPs & Health)');
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(controller.privacyEngine.excludeOtpAndHealth, isTrue);
      expect(mockBridge.mockCategoryRules, contains('otp'));
    });

    testWidgets('filters app list when searching', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPrivacyScreen(controller: controller),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      final searchFinder = find.byType(TextField);
      expect(searchFinder, findsOneWidget);
      await tester.enterText(searchFinder, 'Signal');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SwitchListTile, 'Signal'), findsOneWidget);
      expect(find.widgetWithText(SwitchListTile, 'Telegram'), findsNothing);
      expect(find.widgetWithText(SwitchListTile, 'WhatsApp'), findsNothing);
    });

    testWidgets('toggling app switch updates package blacklist', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPrivacyScreen(controller: controller),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      final signalTile = find.widgetWithText(SwitchListTile, 'Signal');
      expect(signalTile, findsOneWidget);

      await tester.tap(signalTile);
      await tester.pumpAndSettle();

      expect(controller.isPackageBlacklisted('org.thoughtcrime.securesms'), isTrue);
      expect(mockBridge.mockBlacklist, contains('org.thoughtcrime.securesms'));
    });
  });
}
