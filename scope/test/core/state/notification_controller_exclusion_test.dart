import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/app_exclusion_manager.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/database/drift_notification_storage.dart';

class MockBridge extends NotificationBridge {
  List<AppNotification> mockNotifications = [];

  @override
  Future<List<AppNotification>> getNotifications() async {
    return mockNotifications;
  }

  @override
  Future<bool> isListenerEnabled() async {
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationController Pre-Storage Exclusion Tests', () {
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

    test('Default sensitive notifications leave ZERO records in local storage on initial setup', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      mockBridge.mockNotifications = [
        AppNotification(
          id: 'n1',
          packageName: 'com.chase.sig.android', // Banking -> default excluded
          title: 'Debit Alert',
          content: '₹5,000 debited from account',
          timestamp: now,
          category: 'banking',
        ),
        AppNotification(
          id: 'n2',
          packageName: 'com.google.android.apps.authenticator2', // OTP -> default excluded
          title: 'Your OTP',
          content: '882715 is your 2FA code',
          timestamp: now,
          category: 'otp',
        ),
        AppNotification(
          id: 'n3',
          packageName: 'com.myfitnesspal.android', // Health -> default excluded
          title: 'Daily Goal',
          content: 'Log your dinner calories',
          timestamp: now,
          category: 'health',
        ),
        AppNotification(
          id: 'n4',
          packageName: 'com.whatsapp', // Allowed
          title: 'Alice',
          content: 'Hey there!',
          timestamp: now,
          category: 'msg',
        ),
      ];

      await controller.fetchNotifications();

      // Only the WhatsApp notification should be captured and stored
      expect(controller.notifications.length, equals(1));
      expect(controller.notifications.first.packageName, equals('com.whatsapp'));

      // Verify ZERO records stored in local database for sensitive packages
      final dbNotifications = await db.notificationDao.getAll();
      expect(dbNotifications.length, equals(1));
      expect(dbNotifications.first.packageName, equals('com.whatsapp'));

      final chaseRecord = await db.notificationDao.getById('n1');
      expect(chaseRecord, isNull);
    });

    test('Toggling exclusion instantly updates capture filter prior to storage', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Initial state: Chase Bank is excluded by default
      mockBridge.mockNotifications = [
        AppNotification(
          id: 'n10',
          packageName: 'com.chase.sig.android',
          title: 'Balance Alert',
          content: 'Your current balance is \$2,450',
          timestamp: now,
        ),
      ];

      await controller.fetchNotifications();
      expect(controller.notifications, isEmpty);

      // 2. User toggles Chase Bank to ALLOWED in exclusion manager
      await controller.exclusionManager.setExclusion(
        'com.chase.sig.android',
        false, // isExcluded = false
        appName: 'Chase Mobile',
        category: 'banking',
      );

      // 3. Fetch again — now Chase Bank notification IS captured and stored
      mockBridge.mockNotifications = [
        AppNotification(
          id: 'n11',
          packageName: 'com.chase.sig.android',
          title: 'Balance Alert 2',
          content: 'Your current balance is \$2,500',
          timestamp: now + 1000,
        ),
      ];

      await controller.fetchNotifications();
      expect(controller.notifications.length, equals(1));
      expect(controller.notifications.first.id, equals('n11'));

      final dbRecord = await db.notificationDao.getById('n11');
      expect(dbRecord, isNotNull);

      // 4. User toggles Chase Bank back to EXCLUDED
      await controller.exclusionManager.setExclusion(
        'com.chase.sig.android',
        true, // isExcluded = true
      );

      // 5. Next Chase notification is blocked prior to storage
      mockBridge.mockNotifications = [
        AppNotification(
          id: 'n12',
          packageName: 'com.chase.sig.android',
          title: 'Balance Alert 3',
          content: 'Your current balance is \$2,600',
          timestamp: now + 2000,
        ),
      ];

      await controller.fetchNotifications();
      // Storage should still only contain n11, n12 was blocked before persistent storage
      final n12Record = await db.notificationDao.getById('n12');
      expect(n12Record, isNull);
    });
  });
}
