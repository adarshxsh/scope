import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';

class FakeGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'medium',
      priorityScore: 0.50,
      classifiedCategory: 'msg',
      latencyMs: 1,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late NotificationController controller;
  late InMemoryNotificationStorage storage;
  late FakeGhostAnalysisEngine mockEngine;

  setUp(() {
    container = ProviderContainer();
    storage = InMemoryNotificationStorage();
    mockEngine = FakeGhostAnalysisEngine();
    controller = NotificationController(
      container: container,
      storage: storage,
      engine: mockEngine,
    );
  });

  tearDown(() {
    controller.dispose();
    container.dispose();
  });

  group('NotificationController debug mode guards', () {
    test('generateTestData generates notifications and clearAll clears state in debug mode', () async {
      expect(controller.notifications, isEmpty);

      await controller.generateTestData();
      expect(controller.notifications, isNotEmpty);

      final countBeforeClear = controller.notifications.length;
      expect(countBeforeClear, greaterThan(0));

      await controller.clearAll();
      expect(controller.notifications, isEmpty);
      expect(await storage.getAll(), isEmpty);
    });
  });
}
