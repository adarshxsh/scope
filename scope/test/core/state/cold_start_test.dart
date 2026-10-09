import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/widgets/primitives/scope_error_boundary.dart';

class ThrowingNotificationStorage implements NotificationStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<int> get count async => 0;

  @override
  Future<int> deleteOlderThan(int cutoffTimestamp) async => 0;

  @override
  Future<List<AppNotification>> getAll() async {
    throw Exception('Simulated database/storage failure during cold-start');
  }

  @override
  Future<AppNotification?> getById(String id) async => null;

  @override
  Future<void> save(AppNotification notification) async {}

  @override
  Future<void> saveAll(List<AppNotification> notifications) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cold-Start Error Boundaries and Bounded Queue Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('NotificationController completes initial loading if storage throws an exception', () async {
      final controller = NotificationController(
        storage: ThrowingNotificationStorage(),
        container: container,
      );

      // Wait a tick for async load to settle
      await Future.delayed(const Duration(milliseconds: 100));

      expect(controller.isLoading, isFalse);
      controller.dispose();
    });

    test('ReviewQueueNotifier bounds startup rescore processing', () async {
      final notifier = container.read(reviewQueueProvider.notifier);

      // Create 15 test notifications
      final notifs = List.generate(
        15,
        (i) => AppNotification(
          id: 'n_$i',
          packageName: 'com.test.app',
          title: 'Notification $i',
          content: 'Content $i',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          state: ReviewState.ACTIVE,
        ),
      );

      notifier.load(notifs);
      await notifier.rescore(isStartup: true, maxItems: 5);

      // Verify that active notifications exist and queue capacity boundary is respected
      final currentQueue = container.read(reviewQueueProvider);
      expect(currentQueue, isNotEmpty);
      expect(currentQueue.length, lessThanOrEqualTo(ReviewQueueNotifier.maxActiveQueueSize));
    });

    test('ReviewQueueNotifier enforces maxActiveQueueSize capacity limit', () {
      final notifier = container.read(reviewQueueProvider.notifier);

      final notifs = List.generate(
        120,
        (i) => AppNotification(
          id: 'item_$i',
          packageName: 'com.test.app',
          title: 'Item $i',
          content: 'Body $i',
          timestamp: DateTime.now().millisecondsSinceEpoch + i,
          priorityScore: (i % 10) / 10.0,
        ),
      );

      for (final n in notifs) {
        notifier.add(n);
      }

      final activeCount = container
          .read(reviewQueueProvider)
          .where((n) => n.state == ReviewState.ACTIVE)
          .length;

      expect(activeCount, lessThanOrEqualTo(ReviewQueueNotifier.maxActiveQueueSize));
    });

    testWidgets('ScopeErrorBoundary catches build exceptions and displays fallback UI', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScopeErrorBoundary(
            child: Builder(
              builder: (context) {
                throw Exception('Simulated widget build crash on startup');
              },
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNotNull);
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });
  });
}
