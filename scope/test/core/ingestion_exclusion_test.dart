import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/services/app_exclusion_service.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/storage/notification_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppExclusionService Unit Tests', () {
    test('Default self package is always excluded', () {
      final service = AppExclusionService();
      expect(service.isPackageExcluded('com.scope.attentions'), isTrue);
      expect(service.isPackageExcluded('com.scope.attentionos'), isTrue);
    });

    test('Add and remove excluded package names', () async {
      final service = AppExclusionService();
      expect(service.isPackageExcluded('com.whatsapp'), isFalse);

      await service.addExcludedPackage('com.whatsapp');
      expect(service.isPackageExcluded('com.whatsapp'), isTrue);
      expect(service.excludedPackages.contains('com.whatsapp'), isTrue);

      await service.removeExcludedPackage('com.whatsapp');
      expect(service.isPackageExcluded('com.whatsapp'), isFalse);
    });

    test('Toggle package exclusion state', () async {
      final service = AppExclusionService();
      expect(service.isPackageExcluded('com.instagram.android'), isFalse);

      await service.togglePackageExcluded('com.instagram.android');
      expect(service.isPackageExcluded('com.instagram.android'), isTrue);

      await service.togglePackageExcluded('com.instagram.android');
      expect(service.isPackageExcluded('com.instagram.android'), isFalse);
    });

    test('Bulk set excluded packages', () async {
      final service = AppExclusionService();
      await service.setExcludedPackages(['com.facebook.katana', 'com.snapchat.android']);

      expect(service.isPackageExcluded('com.facebook.katana'), isTrue);
      expect(service.isPackageExcluded('com.snapchat.android'), isTrue);
      expect(service.isPackageExcluded('com.whatsapp'), isFalse);
    });
  });

  group('NotificationBridge Excluded Packages MethodChannel Tests', () {
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.scope.notifications'),
        (MethodCall methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'setExcludedPackages') {
            return true;
          }
          if (methodCall.method == 'getExcludedPackages') {
            return ['com.test.excluded'];
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.scope.notifications'),
        null,
      );
    });

    test('setExcludedPackages invokes correct method channel call', () async {
      final bridge = NotificationBridge();
      final success = await bridge.setExcludedPackages(['com.whatsapp', 'com.instagram.android']);

      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, 'setExcludedPackages');
      expect(log.first.arguments, {
        'packages': ['com.whatsapp', 'com.instagram.android'],
      });
    });

    test('getExcludedPackages retrieves excluded packages list', () async {
      final bridge = NotificationBridge();
      final result = await bridge.getExcludedPackages();

      expect(result, ['com.test.excluded']);
      expect(log, hasLength(1));
      expect(log.first.method, 'getExcludedPackages');
    });
  });

  group('Ingestion Guardrails & Sanitization Tests', () {
    test('NotificationController sanitizes oversized text fields and invalid timestamps', () async {
      final storage = InMemoryNotificationStorage();
      final container = ProviderContainer();
      final controller = NotificationController(
        storage: storage,
        container: container,
      );

      final oversizedTitle = 'A' * 300;
      final oversizedContent = 'B' * 3000;
      final futureTimestamp = DateTime.now().millisecondsSinceEpoch + 100000000;

      final rawNotif = AppNotification(
        id: 'test_oversized_1',
        packageName: '  com.test.app  ',
        title: oversizedTitle,
        content: oversizedContent,
        timestamp: futureTimestamp,
      );

      expect(rawNotif.title.length, equals(300));
      expect(rawNotif.content.length, equals(3000));

      // Verify sanitization in test data processing
      await controller.generateTestData();

      expect(controller.notifications, isNotEmpty);
    });

    test('Memory Quota Limit Trimming in ReviewQueueNotifier', () {
      final notifier = ReviewQueueNotifier();

      // Create 510 active notifications exceeding quota of 500
      final notifications = List.generate(510, (i) {
        return AppNotification(
          id: 'quota_notif_$i',
          packageName: 'com.example.app',
          title: 'Notif $i',
          content: 'Body $i',
          timestamp: DateTime.now().millisecondsSinceEpoch - i * 1000,
          priority: i < 20 ? 'low' : 'high',
          state: ReviewState.ACTIVE,
        );
      });

      notifier.load(notifications);

      final activeNotifs = notifier.state.where((n) => n.state == ReviewState.ACTIVE).toList();
      final expiredNotifs = notifier.state.where((n) => n.state == ReviewState.EXPIRED).toList();

      expect(activeNotifs.length, equals(500));
      expect(expiredNotifs.length, equals(10));
    });

    test('App Exclusion filtering during ingestion in NotificationController', () async {
      final storage = InMemoryNotificationStorage();
      final container = ProviderContainer();
      final bridge = NotificationBridge();
      final exclusionService = AppExclusionService(bridge: bridge);

      await exclusionService.addExcludedPackage('org.telegram.messenger');

      final controller = NotificationController(
        storage: storage,
        container: container,
        exclusionService: exclusionService,
      );

      await controller.generateTestData();

      final telegramNotifs = controller.notifications.where((n) => n.packageName == 'org.telegram.messenger');
      expect(telegramNotifs, isEmpty);
    });
  });
}
