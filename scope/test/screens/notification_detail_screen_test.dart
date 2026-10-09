import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class MockUrlLauncherPlatform extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  String? lastLaunchedUrl;
  LaunchOptions? lastOptions;
  bool shouldSucceed = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastLaunchedUrl = url;
    lastOptions = options;
    return shouldSucceed;
  }

  @override
  Future<bool> canLaunch(String url) async => true;
}

class FakeNotificationController extends NotificationController {
  bool recordActionCalled = false;
  bool completeCalled = false;
  String? completedId;

  @override
  void recordAction() {
    recordActionCalled = true;
  }

  @override
  void complete(String id) {
    completeCalled = true;
    completedId = id;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockUrlLauncherPlatform mockLauncher;
  late FakeNotificationController fakeController;

  setUp(() {
    mockLauncher = MockUrlLauncherPlatform();
    UrlLauncherPlatform.instance = mockLauncher;
    fakeController = FakeNotificationController();
  });

  group('NotificationDetailScreen - SmartAction URL Launcher & Sanitization', () {
    testWidgets('launches valid HTTP/HTTPS URL when Open Portal chip is tapped', (tester) async {
      final notification = AppNotification(
        id: 'notif_1',
        packageName: 'com.example.scholarship',
        title: 'Portal Open',
        content: 'Visit portal at https://scholarship.gov.in/portal',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: const {
          'urls': ['https://scholarship.gov.in/portal'],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationDetailScreen(
            notification: notification,
            controller: fakeController,
          ),
        ),
      );

      expect(find.text('Open Portal'), findsOneWidget);

      await tester.tap(find.text('Open Portal'));
      await tester.pumpAndSettle();

      expect(mockLauncher.lastLaunchedUrl, equals('https://scholarship.gov.in/portal'));
      expect(mockLauncher.lastOptions?.mode, equals(PreferredLaunchMode.externalApplication));
      expect(fakeController.recordActionCalled, isTrue);
      expect(fakeController.completeCalled, isTrue);
      expect(fakeController.completedId, equals('notif_1'));
    });

    testWidgets('blocks execution and displays safety warning snackbar for forbidden URI schemes', (tester) async {
      final notification = AppNotification(
        id: 'notif_2',
        packageName: 'com.example.malicious',
        title: 'File Alert',
        content: 'Check local file file:///etc/passwd',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: const {
          'urls': ['file:///etc/passwd'],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationDetailScreen(
            notification: notification,
            controller: fakeController,
          ),
        ),
      );

      await tester.tap(find.text('Open Website'));
      await tester.pumpAndSettle();

      // Verify Safety Warning snackbar is displayed
      expect(
        find.textContaining('Safety Warning: Blocked unsafe URL scheme in "file:///etc/passwd"'),
        findsOneWidget,
      );
      // Verify url_launcher was NOT called
      expect(mockLauncher.lastLaunchedUrl, isNull);
      // Verify metrics and notification state were NOT changed
      expect(fakeController.recordActionCalled, isFalse);
      expect(fakeController.completeCalled, isFalse);
    });

    testWidgets('displays error snackbar and preserves screen state if url_launcher fails', (tester) async {
      mockLauncher.shouldSucceed = false;

      final notification = AppNotification(
        id: 'notif_4',
        packageName: 'com.example.app',
        title: 'Broken Link',
        content: 'Visit https://broken-link.org',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        extractedFeatures: const {
          'urls': ['https://broken-link.org'],
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationDetailScreen(
            notification: notification,
            controller: fakeController,
          ),
        ),
      );

      await tester.tap(find.text('Open Website'));
      await tester.pumpAndSettle();

      expect(mockLauncher.lastLaunchedUrl, equals('https://broken-link.org'));
      expect(find.text('Could not launch URL: https://broken-link.org'), findsOneWidget);
      expect(fakeController.recordActionCalled, isFalse);
      // Screen remains visible
      expect(find.text('Ghost AI Analysis'), findsOneWidget);
    });
  });
}
