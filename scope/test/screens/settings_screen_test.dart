import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/bridge/notification_bridge.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/screens/settings_screen.dart';

class MockNotificationStorage implements NotificationStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<int> get count async => 0;

  @override
  Future<int> deleteOlderThan(int timestamp) async => 0;

  @override
  Future<List<AppNotification>> getAll() async => [];

  @override
  Future<AppNotification?> getById(String id) async => null;

  @override
  Future<void> save(AppNotification notification) async {}

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {}
}

class MockNotificationBridge extends NotificationBridge {
  @override
  Future<bool> isListenerEnabled() async => true;

  @override
  Future<void> openNotificationSettings() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen Widget Tests', () {
    late AttentionDatabase db;
    late ProviderContainer container;
    late NotificationController controller;

    setUp(() {
      db = AttentionDatabase.inMemory();
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      controller = NotificationController(
        storage: MockNotificationStorage(),
        bridge: MockNotificationBridge(),
        container: container,
      );
    });

    tearDown(() async {
      controller.dispose();
      container.dispose();
      await db.close();
    });

    testWidgets('renders SettingsScreen tiles', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SettingsScreen(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Ghost AI Engine'), findsOneWidget);
      expect(find.text('Privacy'), findsOneWidget);
    });
  });
}
