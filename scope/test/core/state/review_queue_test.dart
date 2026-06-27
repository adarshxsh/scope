import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/state/notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReviewQueueNotifier Tests', () {
    late ProviderContainer container;
    late ReviewQueueNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(reviewQueueProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('starts with an empty queue state', () {
      expect(container.read(reviewQueueProvider), isEmpty);
    });

    test('add() inserts a notification in ACTIVE state and updates lastUpdated', () {
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hey there',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      notifier.add(notif);

      final list = container.read(reviewQueueProvider);
      expect(list.length, equals(1));
      expect(list.first.id, equals('n1'));
      expect(list.first.state, equals(ReviewState.ACTIVE));
      expect(list.first.lastUpdated, isNotNull);
    });

    test('remove() deletes a notification from state', () {
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hey there',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      notifier.add(notif);
      expect(container.read(reviewQueueProvider).length, equals(1));

      notifier.remove('n1');
      expect(container.read(reviewQueueProvider), isEmpty);
    });

    test('archive() and expire() transition states correctly', () {
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hey there',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      notifier.add(notif);

      notifier.archive('n1');
      expect(container.read(reviewQueueProvider).first.state, equals(ReviewState.ARCHIVED));

      notifier.expire('n1');
      expect(container.read(reviewQueueProvider).first.state, equals(ReviewState.EXPIRED));
    });

    test('snooze() transitions state to SNOOZED and sets snoozedUntil', () {
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hey there',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      notifier.add(notif);
      notifier.snooze('n1', const Duration(hours: 2));

      final item = container.read(reviewQueueProvider).first;
      expect(item.state, equals(ReviewState.SNOOZED));
      expect(item.snoozedUntil, isNotNull);
      expect(item.snoozedUntil!.isAfter(DateTime.now().add(const Duration(minutes: 110))), isTrue);
    });

    test('rescore() un-snoozes notifications whose snooze duration has elapsed', () async {
      final notif = AppNotification(
        id: 'n1',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Hey there',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      notifier.add(notif);
      // Snooze with negative duration so it is immediately expired
      notifier.snooze('n1', const Duration(seconds: -10));

      final snoozedItem = container.read(reviewQueueProvider).first;
      expect(snoozedItem.state, equals(ReviewState.SNOOZED));

      await notifier.rescore();

      final rescoredItem = container.read(reviewQueueProvider).first;
      expect(rescoredItem.state, equals(ReviewState.ACTIVE));
    });

    test('merge duplicate notifications correctly', () {
      final notif1 = AppNotification(
        id: 'original-id',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Dinner tonight?',
        timestamp: DateTime.now().millisecondsSinceEpoch - 10000,
      );

      final notif2 = AppNotification(
        id: 'new-id',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Dinner tonight?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      notifier.add(notif1);
      notifier.snooze('original-id', const Duration(minutes: 5)); // Set to snoozed

      notifier.add(notif2); // Duplicate add

      final list = container.read(reviewQueueProvider);
      expect(list.length, equals(1));
      expect(list.first.id, equals('original-id')); // Preserved original ID
      expect(list.first.state, equals(ReviewState.ACTIVE)); // Reset to ACTIVE
      expect(list.first.snoozedUntil, isNull); // Snooze cleared
    });

    test('rescore() auto-expires OTPs whose duration has elapsed', () async {
      final oldOtp = AppNotification(
        id: 'otp-old',
        packageName: 'com.whatsapp',
        title: 'OTP Verification',
        content: 'Your verification code is 883102. Valid for 5 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch - 6 * 60 * 1000, // 6 minutes ago
      );

      notifier.add(oldOtp);
      await notifier.rescore();

      final item = container.read(reviewQueueProvider).first;
      expect(item.state, equals(ReviewState.EXPIRED));
      expect(item.priorityScore, equals(0.0));
    });

    test('rescore() auto-expires relative deadline reminders after they pass', () async {
      final oldReminder = AppNotification(
        id: 'rem-old',
        packageName: 'com.google.android.calendar',
        title: 'Upcoming meeting reminder',
        content: 'Starts in 10 minutes',
        timestamp: DateTime.now().millisecondsSinceEpoch - 11 * 60 * 1000, // 11 minutes ago
      );

      notifier.add(oldReminder);
      await notifier.rescore();

      final item = container.read(reviewQueueProvider).first;
      expect(item.state, equals(ReviewState.EXPIRED));
      expect(item.priorityScore, equals(0.0));
    });

    test('rescore() auto-archives completed payment reminders', () async {
      final completedPayment = AppNotification(
        id: 'pay-done',
        packageName: 'com.jio.myjio',
        title: 'Broadband Bill payment reminder',
        content: 'Broadband bill of Rs 799 payment successful',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      notifier.add(completedPayment);
      await notifier.rescore();

      final item = container.read(reviewQueueProvider).first;
      expect(item.state, equals(ReviewState.ARCHIVED));
    });
  });

  group('Queue Sorting and Filtering Tests', () {
    late ProviderContainer container;
    late ReviewQueueNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(reviewQueueProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('filters out archived and snoozed notifications from active sorted queue', () {
      final active = AppNotification(id: 'a1', packageName: 'whatsapp', title: 'A', content: 'Act', timestamp: 1);
      final archived = AppNotification(id: 'a2', packageName: 'whatsapp', title: 'B', content: 'Arc', timestamp: 2, state: ReviewState.ARCHIVED);
      final snoozed = AppNotification(id: 'a3', packageName: 'whatsapp', title: 'C', content: 'Snooze', timestamp: 3, state: ReviewState.SNOOZED, snoozedUntil: DateTime.now().add(const Duration(minutes: 5)));

      notifier.add(active);
      notifier.add(archived);
      notifier.add(snoozed);

      // Force archive state directly for a2 since add() resets state to ACTIVE
      notifier.archive('a2');
      notifier.snooze('a3', const Duration(minutes: 5));

      final sortedQueue = container.read(sortedReviewQueueProvider);
      expect(sortedQueue.length, equals(1));
      expect(sortedQueue.first.id, equals('a1'));
    });

    test('sorts by review score descending', () {
      final low = AppNotification(id: 'low', packageName: 'promo', title: 'Promo', content: 'Buy', timestamp: 1, priorityScore: 0.1);
      final high = AppNotification(id: 'high', packageName: 'whatsapp', title: 'Mom', content: 'Emergency', timestamp: 2, priorityScore: 0.95);
      final mid = AppNotification(id: 'mid', packageName: 'gmail', title: 'Work', content: 'Updates', timestamp: 3, priorityScore: 0.5);

      notifier.add(low);
      notifier.add(high);
      notifier.add(mid);

      // Manually set priorityScores (since add() copyWith might run prediction fallback)
      notifier.update(low.copyWith(priorityScore: 0.10));
      notifier.update(high.copyWith(priorityScore: 0.95));
      notifier.update(mid.copyWith(priorityScore: 0.50));

      container.read(reviewQueueSortOrderProvider.notifier).state = QueueSortOrder.reviewScore;

      final sorted = container.read(sortedReviewQueueProvider);
      expect(sorted.length, equals(3));
      expect(sorted[0].id, equals('high'));
      expect(sorted[1].id, equals('mid'));
      expect(sorted[2].id, equals('low'));
    });

    test('sorts by deadline ascending (closer deadlines first)', () {
      final far = AppNotification(id: 'far', packageName: 'cal', title: 'meeting reminder', content: 'starts in 60 minutes', timestamp: DateTime.now().millisecondsSinceEpoch);
      final near = AppNotification(id: 'near', packageName: 'cal', title: 'meeting reminder', content: 'starts in 5 minutes', timestamp: DateTime.now().millisecondsSinceEpoch);
      final none = AppNotification(id: 'none', packageName: 'whatsapp', title: 'Chat', content: 'Hello', timestamp: DateTime.now().millisecondsSinceEpoch - 5000);

      notifier.add(far);
      notifier.add(near);
      notifier.add(none);

      // Verify and set deadline features manually to match FeatureExtractor representation
      notifier.update(far.copyWith(extractedFeatures: {'deadline_minutes_remaining': 60}));
      notifier.update(near.copyWith(extractedFeatures: {'deadline_minutes_remaining': 5}));
      notifier.update(none.copyWith(extractedFeatures: {'deadline_minutes_remaining': -1}));

      container.read(reviewQueueSortOrderProvider.notifier).state = QueueSortOrder.deadline;

      final sorted = container.read(sortedReviewQueueProvider);
      expect(sorted.length, equals(3));
      expect(sorted[0].id, equals('near')); // Closer deadline first
      expect(sorted[1].id, equals('far'));
      expect(sorted[2].id, equals('none')); // No deadline last
    });

    test('sorts by lastUpdated descending', () {
      final now = DateTime.now();
      final item1 = AppNotification(id: 'i1', packageName: 'whatsapp', title: 'A', content: 'Msg', timestamp: 10, lastUpdated: now.subtract(const Duration(minutes: 10)));
      final item2 = AppNotification(id: 'i2', packageName: 'whatsapp', title: 'B', content: 'Msg', timestamp: 20, lastUpdated: now);
      final item3 = AppNotification(id: 'i3', packageName: 'whatsapp', title: 'C', content: 'Msg', timestamp: 30, lastUpdated: now.subtract(const Duration(minutes: 5)));

      notifier.add(item1);
      notifier.add(item2);
      notifier.add(item3);

      notifier.update(item1.copyWith(lastUpdated: now.subtract(const Duration(minutes: 10))));
      notifier.update(item2.copyWith(lastUpdated: now));
      notifier.update(item3.copyWith(lastUpdated: now.subtract(const Duration(minutes: 5))));

      container.read(reviewQueueSortOrderProvider.notifier).state = QueueSortOrder.lastUpdated;

      final sorted = container.read(sortedReviewQueueProvider);
      expect(sorted.length, equals(3));
      expect(sorted[0].id, equals('i2')); // newest updated first
      expect(sorted[1].id, equals('i3'));
      expect(sorted[2].id, equals('i1'));
    });
  });

  group('NotificationController Integration Tests', () {
    late ProviderContainer container;
    late NotificationController controller;

    setUp(() {
      container = ProviderContainer();
      controller = NotificationController(container: container);
    });

    tearDown(() {
      container.dispose();
      controller.dispose();
    });

    test('adds test data and synchronizes controller notifications with Riverpod providers', () async {
      await controller.generateTestData();

      expect(controller.notifications, isNotEmpty);
      expect(container.read(reviewQueueProvider), isNotEmpty);
      expect(controller.notifications.length, equals(container.read(reviewQueueProvider).length));
    });

    test('completing and archiving in controller updates review states inside Riverpod', () async {
      final notif = AppNotification(
        id: 'c1',
        packageName: 'whatsapp',
        title: 'Alice',
        content: 'Hello',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      container.read(reviewQueueProvider.notifier).add(notif);

      // Archive test
      controller.archive('c1');
      expect(controller.isArchived('c1'), isTrue);
      expect(container.read(reviewQueueProvider).first.state, equals(ReviewState.ARCHIVED));

      // Complete test
      controller.complete('c1');
      expect(controller.isCompleted('c1'), isTrue);
      expect(container.read(reviewQueueProvider).first.state, equals(ReviewState.REVIEWED));
    });
  });
}
