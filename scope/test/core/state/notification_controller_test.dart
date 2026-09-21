import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MockNotificationStorage implements NotificationStorage {
  final List<AppNotification> items = [];
  bool shouldThrowOnSave = false;

  @override
  Future<void> save(AppNotification notification) async {
    if (shouldThrowOnSave) throw Exception('Storage write error');
    items.add(notification);
  }

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {
    if (shouldThrowOnSave) throw Exception('Storage write error');
    items.addAll(notifications);
  }

  @override
  Future<int> get count async => items.length;

  @override
  Future<int> deleteOlderThan(int cutoffTimestamp) async {
    final before = items.length;
    items.removeWhere((n) => n.timestamp < cutoffTimestamp);
    return before - items.length;
  }

  @override
  Future<List<AppNotification>> getAll() async {
    return items;
  }

  @override
  Future<void> clear() async {
    items.clear();
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((n) => n.id == id);
  }

  @override
  Future<AppNotification?> getById(String id) async {
    try {
      return items.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> update(AppNotification notification) async {
    final index = items.indexWhere((n) => n.id == notification.id);
    if (index >= 0) {
      items[index] = notification;
    }
  }
}

class FakeMethodChannelBridge extends NotificationBridge {
  final List<AppNotification> pendingNativeNotifications;
  final List<List<String>> acknowledgedBatches = [];

  FakeMethodChannelBridge(this.pendingNativeNotifications, {super.channel});

  @override
  Future<List<AppNotification>> getNotifications() async {
    return List.from(pendingNativeNotifications);
  }

  @override
  Future<bool> acknowledgeNotifications(List<String> ids) async {
    acknowledgedBatches.add(ids);
    pendingNativeNotifications.removeWhere((n) => ids.contains(n.id));
    return true;
  }

  @override
  Future<bool> isListenerEnabled() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('NotificationController Two-Phase Handshake', () {
    test('acknowledges batch IDs only after successful storage persistence', () async {
      final notif1 = AppNotification(
        id: 'notif_1',
        packageName: 'com.test.app',
        title: 'Title 1',
        content: 'Content 1',
        timestamp: 1700000000000,
      );
      final notif2 = AppNotification(
        id: 'notif_2',
        packageName: 'com.test.app',
        title: 'Title 2',
        content: 'Content 2',
        timestamp: 1700000001000,
      );

      final bridge = FakeMethodChannelBridge([notif1, notif2]);
      final storage = MockNotificationStorage();
      final engine = GhostAnalysisEngine();

      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
        container: container,
      );

      await controller.fetchNotifications();

      // Storage should contain saved items
      expect(storage.items.length, 2);
      // Bridge should have received acknowledgement call for ['notif_1', 'notif_2']
      expect(bridge.acknowledgedBatches.length, 1);
      expect(bridge.acknowledgedBatches.single, ['notif_1', 'notif_2']);
      // Native pending queue should now be empty
      expect(bridge.pendingNativeNotifications, isEmpty);
    });

    test('does NOT acknowledge if storage persistence throws exception', () async {
      final notif1 = AppNotification(
        id: 'notif_10',
        packageName: 'com.test.app',
        title: 'Critical Alert',
        content: 'Important message',
        timestamp: 1700000000000,
      );

      final bridge = FakeMethodChannelBridge([notif1]);
      final storage = MockNotificationStorage()..shouldThrowOnSave = true;
      final engine = GhostAnalysisEngine();

      final controller = NotificationController(
        bridge: bridge,
        storage: storage,
        engine: engine,
        container: container,
      );

      await controller.fetchNotifications();

      // Acknowledgment should NOT have been sent because storage save failed
      expect(bridge.acknowledgedBatches, isEmpty);
      // Notification remains staged in native bridge memory for re-fetching
      expect(bridge.pendingNativeNotifications.length, 1);
      expect(bridge.pendingNativeNotifications.single.id, 'notif_10');

      // Now fix storage write error and re-fetch on next cycle
      storage.shouldThrowOnSave = false;
      await controller.fetchNotifications();

      // Second cycle succeeds and acknowledges
      expect(bridge.acknowledgedBatches.length, 1);
      expect(bridge.acknowledgedBatches.single, ['notif_10']);
      expect(bridge.pendingNativeNotifications, isEmpty);
    });
  });
}
