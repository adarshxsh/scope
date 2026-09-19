import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Telemetry Retention, Logging, and Quota Governance Tests', () {
    late ProviderContainer container;
    late NotificationController controller;
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase.inMemory();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      controller = NotificationController(container: container);
    });

    tearDown(() async {
      controller.dispose();
      container.dispose();
      await db.close();
    });

    test('Retention period update triggers state change and immediate cleanup', () async {
      expect(controller.retentionDays, equals(7));

      final now = DateTime.now().millisecondsSinceEpoch;
      final oldNotif = AppNotification(
        id: 'n-10-days-old',
        packageName: 'com.test',
        title: 'Old Notice',
        content: 'Old',
        timestamp: now - (10 * 86400 * 1000),
      );
      final newNotif = AppNotification(
        id: 'n-2-days-old',
        packageName: 'com.test',
        title: 'New Notice',
        content: 'New',
        timestamp: now - (2 * 86400 * 1000),
      );

      // Insert both into database & notifier
      await db.notificationDao.insertNotification(NotificationEntry(
        id: oldNotif.id,
        packageName: oldNotif.packageName,
        title: oldNotif.title,
        content: oldNotif.content,
        timestamp: oldNotif.timestamp,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      ));
      await db.notificationDao.insertNotification(NotificationEntry(
        id: newNotif.id,
        packageName: newNotif.packageName,
        title: newNotif.title,
        content: newNotif.content,
        timestamp: newNotif.timestamp,
        state: ReviewState.ACTIVE,
        reviewed: false,
        dismissed: false,
        isOngoing: false,
        createdAt: DateTime.now(),
      ));

      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 1,
        notificationId: oldNotif.id,
        priority: 'medium',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));
      await db.reviewQueueDao.insertItem(ReviewQueueEntry(
        id: 2,
        notificationId: newNotif.id,
        priority: 'medium',
        enqueueTime: DateTime.now(),
        status: ReviewState.ACTIVE,
      ));

      // Set retention days to 3 days
      await controller.setRetentionDays(3);

      expect(controller.retentionDays, equals(3));
      final allNotifs = await db.notificationDao.getAll();
      final remainingIds = allNotifs.map((n) => n.id).toList();
      expect(remainingIds, isNot(contains('n-10-days-old')));
      expect(remainingIds, contains('n-2-days-old'));
    });

    test('Telemetry logging toggle updates controller state and GhostAI setting', () async {
      expect(controller.telemetryLoggingEnabled, isTrue);
      expect(GhostAI.instance.isTelemetryLoggingEnabled, isTrue);

      await controller.setTelemetryLoggingEnabled(false);

      expect(controller.telemetryLoggingEnabled, isFalse);
      expect(GhostAI.instance.isTelemetryLoggingEnabled, isFalse);

      await controller.setTelemetryLoggingEnabled(true);

      expect(controller.telemetryLoggingEnabled, isTrue);
      expect(GhostAI.instance.isTelemetryLoggingEnabled, isTrue);
    });

    test('Storage quota cap enforcement purges excess oldest notifications', () async {
      expect(controller.storageQuotaCap, equals(1000));

      final now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < 10; i++) {
        await db.notificationDao.insertNotification(NotificationEntry(
          id: 'n-quota-$i',
          packageName: 'com.test',
          title: 'Notif $i',
          content: 'Content $i',
          timestamp: now + (i * 1000),
          state: ReviewState.ACTIVE,
          reviewed: false,
          dismissed: false,
          isOngoing: false,
          createdAt: DateTime.now(),
        ));
        await db.reviewQueueDao.insertItem(ReviewQueueEntry(
          id: i + 10,
          notificationId: 'n-quota-$i',
          priority: 'medium',
          enqueueTime: DateTime.now(),
          status: ReviewState.ACTIVE,
        ));
      }

      // Set storage quota cap to 5
      await controller.setStorageQuotaCap(5);

      expect(controller.storageQuotaCap, equals(5));

      final allNotifs = await db.notificationDao.getAll();
      expect(allNotifs.length, equals(5));
      final remainingIds = allNotifs.map((n) => n.id).toList();
      expect(remainingIds, containsAll(['n-quota-5', 'n-quota-6', 'n-quota-7', 'n-quota-8', 'n-quota-9']));
      expect(remainingIds, isNot(contains('n-quota-0')));
      expect(remainingIds, isNot(contains('n-quota-1')));
    });

    testWidgets('SettingsScreen renders interactive controls and updates preferences on interaction', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(controller: controller),
          ),
        ),
      );

      // Verify Section Header and Privacy & Governance section
      expect(find.text('PRIVACY & GOVERNANCE'), findsOneWidget);
      expect(find.text('Retention Period'), findsOneWidget);
      expect(find.text('Telemetry Event Logging'), findsOneWidget);
      expect(find.text('Storage Quota Cap'), findsOneWidget);

      // Verify switch is present
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      // Toggle switch
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(controller.telemetryLoggingEnabled, isFalse);
    });
  });
}
