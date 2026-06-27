import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 7 State Consistency and Focus Queue Tests', () {
    late ProviderContainer container;
    late NotificationController controller;

    setUp(() {
      container = ProviderContainer();
      controller = NotificationController(container: container);
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    test('Stable ID generation using DJB2 hashing', () {
      final id1 = AppNotification.generateStableId(
        packageName: 'com.whatsapp',
        timestamp: 1625097600000,
        title: 'Alice',
        content: 'Hello Mom',
      );

      final id2 = AppNotification.generateStableId(
        packageName: 'com.whatsapp',
        timestamp: 1625097600000,
        title: 'Alice',
        content: 'Hello Mom',
      );

      final id3 = AppNotification.generateStableId(
        packageName: 'com.whatsapp',
        timestamp: 1625097600001, // different timestamp
        title: 'Alice',
        content: 'Hello Mom',
      );

      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
      expect(id1, contains('1625097600000'));
    });

    test('Filter type and area propagation', () {
      expect(controller.filterType, equals(FocusFilterType.none));
      expect(controller.focusAreaFilter, isNull);

      controller.setFilter(FocusFilterType.needsAction);
      expect(controller.filterType, equals(FocusFilterType.needsAction));

      controller.setFilter(FocusFilterType.focusArea, FocusArea.finance);
      expect(controller.filterType, equals(FocusFilterType.focusArea));
      expect(controller.focusAreaFilter, equals(FocusArea.finance));

      controller.clearFilter();
      expect(controller.filterType, equals(FocusFilterType.none));
      expect(controller.focusAreaFilter, isNull);
    });

    test('Focus Session queue logic, skip re-ordering, and progress', () {
      final notif1 = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hello',
        timestamp: 1000,
        state: ReviewState.ACTIVE,
      );
      final notif2 = AppNotification(
        id: 'n2',
        packageName: 'com.gmail',
        title: 'Work Email',
        content: 'Project update',
        timestamp: 2000,
        state: ReviewState.ACTIVE,
      );

      // Add notifications to Riverpod review queue
      container.read(reviewQueueProvider.notifier).load([notif1, notif2]);

      expect(controller.reviewQueue.length, equals(2));

      // Start focus session
      controller.startFocusSession();
      expect(controller.inFocusSession, isTrue);
      expect(controller.focusSessionQueueIds, equals(['n1', 'n2']));
      expect(controller.currentFocusNotification!.id, equals('n1'));
      expect(controller.focusSessionProgressCount, equals(0));

      // Skip item 'n1' -> moves to the end of the queue
      controller.skipFocusSessionItem('n1');
      expect(controller.focusSessionQueueIds, equals(['n2', 'n1']));
      expect(controller.currentFocusNotification!.id, equals('n2'));

      // Archive item 'n2' (removes it from active reviewQueue)
      controller.archive('n2');
      expect(controller.focusSessionProgressCount, equals(1)); // n2 is no longer active
      expect(controller.currentFocusNotification!.id, equals('n1'));

      // Complete item 'n1' (removes it from active reviewQueue)
      controller.complete('n1');
      expect(controller.focusSessionProgressCount, equals(2));
      expect(controller.currentFocusNotification, isNull); // session complete
    });
  });
}
