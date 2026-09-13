import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/providers.dart';

void main() {
  group('Notification Queue Capacity Guardrails & Eviction Tests', () {
    late ProviderContainer container;
    late ReviewQueueNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(reviewQueueProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('enforces maxQueueCapacity limit when adding notifications beyond capacity', () {
      final capacity = ReviewQueueNotifier.maxQueueCapacity;

      // Add (capacity + 20) notifications
      for (int i = 0; i < capacity + 20; i++) {
        notifier.add(
          AppNotification(
            id: 'notif_$i',
            packageName: 'com.example.app',
            title: 'Title $i',
            content: 'Body $i',
            timestamp: 1000000 + i,
          ),
        );
      }

      final currentQueue = container.read(reviewQueueProvider);
      expect(currentQueue.length, equals(capacity));
      // Oldest notifications (notif_0 to notif_19) should have been evicted via FIFO
      expect(currentQueue.any((n) => n.id == 'notif_0'), isFalse);
      expect(currentQueue.any((n) => n.id == 'notif_20'), isTrue);
    });

    test('evicts non-active (archived/reviewed/expired) items first before active items on capacity overflow', () {
      final capacity = ReviewQueueNotifier.maxQueueCapacity;

      // Fill queue up to capacity - 5
      for (int i = 0; i < capacity - 5; i++) {
        notifier.add(
          AppNotification(
            id: 'active_$i',
            packageName: 'com.example.app',
            title: 'Active $i',
            content: 'Body $i',
            timestamp: 1000000 + i,
          ),
        );
      }

      // Add 5 notifications and mark them archived
      for (int i = 0; i < 5; i++) {
        notifier.add(
          AppNotification(
            id: 'inactive_$i',
            packageName: 'com.example.app',
            title: 'Inactive $i',
            content: 'Body $i',
            timestamp: 2000000 + i,
          ),
        );
        notifier.archive('inactive_$i');
      }

      expect(container.read(reviewQueueProvider).length, equals(capacity));

      // Now add 10 new active notifications pushing over capacity
      for (int i = 0; i < 10; i++) {
        notifier.add(
          AppNotification(
            id: 'new_$i',
            packageName: 'com.example.app',
            title: 'New $i',
            content: 'Body $i',
            timestamp: 3000000 + i,
          ),
        );
      }

      final queue = container.read(reviewQueueProvider);
      expect(queue.length, equals(capacity));

      // Inactive items should have been evicted first
      for (int i = 0; i < 5; i++) {
        expect(queue.any((n) => n.id == 'inactive_$i'), isFalse);
      }
    });

    test('enforces maxQueueCapacity on load() startup recovery', () {
      final capacity = ReviewQueueNotifier.maxQueueCapacity;
      final oversizedList = List.generate(
        capacity + 50,
        (i) => AppNotification(
          id: 'load_$i',
          packageName: 'com.example.app',
          title: 'Load Title $i',
          content: 'Load Content $i',
          timestamp: 1000000 + i,
        ),
      );

      notifier.load(oversizedList);

      final queue = container.read(reviewQueueProvider);
      expect(queue.length, equals(capacity));
    });
  });
}
