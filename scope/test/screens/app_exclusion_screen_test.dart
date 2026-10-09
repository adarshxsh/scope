import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/privacy/app_exclusion_manager.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/database/drift_notification_storage.dart';
import 'package:scope/screens/app_exclusion_screen.dart';

class MockBridge extends NotificationBridge {
  @override
  Future<bool> isListenerEnabled() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppExclusionScreen Widget Tests', () {
    late AttentionDatabase db;
    late MockBridge mockBridge;
    late AppExclusionManager exclusionManager;
    late NotificationController controller;
    late ProviderContainer container;

    setUp(() async {
      db = AttentionDatabase.inMemory();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      mockBridge = MockBridge();
      exclusionManager = AppExclusionManager(db);
      await exclusionManager.init();

      controller = NotificationController(
        bridge: mockBridge,
        storage: DriftNotificationStorage(db),
        exclusionManager: exclusionManager,
        container: container,
      );
    });

    tearDown(() async {
      controller.dispose();
      container.dispose();
      await db.close();
    });

    Widget createWidgetUnderTest() {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppExclusionScreen(controller: controller),
        ),
      );
    }

    testWidgets('Renders header, search bar, filter chips, and app list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('App Exclusion Manager'), findsOneWidget);
      expect(find.text('Privacy Guardrails'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Banking'), findsOneWidget);
      expect(find.text('OTP / 2FA'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);

      // Verify Chase Mobile or Google Authenticator are rendered
      expect(find.text('Chase Mobile'), findsOneWidget);
      expect(find.text('Google Authenticator'), findsOneWidget);
    });

    testWidgets('Searching filters the applications list by app name or package name', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Search for "Chase"
      await tester.enterText(find.byType(TextField), 'Chase');
      await tester.pumpAndSettle();

      expect(find.text('Chase Mobile'), findsOneWidget);
      expect(find.text('Google Authenticator'), findsNothing);

      // Search for non-existent app
      await tester.enterText(find.byType(TextField), 'NonExistentApp123');
      await tester.pumpAndSettle();

      expect(find.text('No applications found'), findsOneWidget);
    });

    testWidgets('Toggling switch updates exclusion state', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Chase Mobile is initially Blocked
      expect(exclusionManager.isExcluded('com.chase.sig.android'), isTrue);

      // Find switch associated with Chase Mobile and tap it
      final chaseFinder = find.ancestor(
        of: find.text('Chase Mobile'),
        matching: find.byType(ListTile),
      );
      expect(chaseFinder, findsOneWidget);

      final switchFinder = find.descendant(
        of: chaseFinder,
        matching: find.byType(Switch),
      );
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Verify state was updated to Allowed
      expect(exclusionManager.isExcluded('com.chase.sig.android'), isFalse);
    });
  });
}
