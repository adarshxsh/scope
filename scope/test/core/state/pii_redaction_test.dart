import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/storage/notification_storage.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/screens/notification_detail_screen.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('In-Memory PII Redaction Tests', () {
    late ProviderContainer container;
    late InMemoryNotificationStorage storage;
    late GhostAnalysisEngine engine;
    late NotificationController controller;

    setUp(() async {
      container = ProviderContainer();
      storage = InMemoryNotificationStorage();
      engine = GhostAnalysisEngine();
      await engine.initialize();

      controller = NotificationController(
        storage: storage,
        engine: engine,
        container: container,
      );
    });

    tearDown(() {
      controller.dispose();
      container.dispose();
    });

    test('NotificationController and ReviewQueueNotifier store redacted titles/contents in memory', () async {
      final rawNotification = AppNotification(
        id: 'pii-test-1',
        packageName: 'com.bank.app',
        title: r'Payment of $250.00 to john@example.com',
        content: 'Your OTP code is 948201. Card ending in 4111222233334444. Call +14155552671.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Save raw to storage first (simulating database ingestion)
      await storage.save(rawNotification);

      // Load into review queue
      final notifier = container.read(reviewQueueProvider.notifier);
      notifier.add(rawNotification);

      // Check ReviewQueueNotifier state
      final queueState = container.read(reviewQueueProvider);
      expect(queueState.length, equals(1));
      final redacted = queueState.first;

      // Verify state fields are sanitized
      expect(redacted.title, contains('[REDACTED_AMOUNT]'));
      expect(redacted.title, contains('[REDACTED_EMAIL]'));
      expect(redacted.title, isNot(contains(r'$250.00')));
      expect(redacted.title, isNot(contains('john@example.com')));

      expect(redacted.content, contains('[REDACTED_OTP]'));
      expect(redacted.content, contains('[REDACTED_CARD]'));
      expect(redacted.content, contains('[REDACTED_PHONE]'));
      expect(redacted.content, isNot(contains('948201')));
      expect(redacted.content, isNot(contains('4111222233334444')));
      expect(redacted.content, isNot(contains('+14155552671')));
    });

    test('Analysis Engine extracts features from raw notification prior to in-memory sanitization', () async {
      final rawNotification = AppNotification(
        id: 'pii-test-2',
        packageName: 'com.bank.app',
        title: r'Payment reminder $150.00',
        content: 'Your verification OTP is 123456. Valid for 5 minutes.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(rawNotification);

      // Extracted features must not be corrupted by memory redaction
      expect(analyzed.extractedFeatures, isNotNull);
      expect(analyzed.extractedFeatures!['otp'], equals('123456'));
      expect(analyzed.extractedFeatures!['amount'], equals(150.0));

      // Save analyzed (unredacted) to storage and load into state
      await storage.save(analyzed);
      final notifier = container.read(reviewQueueProvider.notifier);
      notifier.load([analyzed]);

      final stateItem = container.read(reviewQueueProvider).first;

      // State is redacted...
      expect(stateItem.title, contains('[REDACTED_AMOUNT]'));
      expect(stateItem.content, contains('[REDACTED_OTP]'));

      // ...but extracted features are preserved!
      expect(stateItem.extractedFeatures, isNotNull);
      expect(stateItem.extractedFeatures!['otp'], equals('123456'));
      expect(stateItem.extractedFeatures!['amount'], equals(150.0));
    });

    test('Unredacted notification details are preserved in storage', () async {
      final rawNotification = AppNotification(
        id: 'pii-test-3',
        packageName: 'com.bank.app',
        title: r'Transfer $500.00',
        content: 'Your code is 888999.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await storage.save(rawNotification);

      // Fetch from storage directly
      final stored = await controller.getNotificationById('pii-test-3');
      expect(stored, isNotNull);
      expect(stored!.title, equals(r'Transfer $500.00'));
      expect(stored.content, equals('Your code is 888999.'));
    });

    testWidgets('NotificationDetailScreen fetches unredacted details from local storage on demand', (tester) async {
      final rawNotification = AppNotification(
        id: 'pii-detail-test',
        packageName: 'com.bank.app',
        title: r'Unredacted Title $500.00',
        content: 'Unredacted Content with OTP 654321',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // Save raw to storage
      await storage.save(rawNotification);

      // Create redacted copy for passing as route arguments (simulating navigation from feed/queue)
      final redactedNotification = rawNotification.copyWith(
        title: 'Redacted Title [REDACTED_AMOUNT]',
        content: 'Redacted Content with OTP [REDACTED_OTP]',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NotificationDetailScreen(
            notification: redactedNotification,
            controller: controller,
          ),
        ),
      );

      // Allow async initState _loadUnredacted to complete
      await tester.pumpAndSettle();

      // Verify screen rendered unredacted details fetched from storage
      expect(find.textContaining(r'Unredacted Title $500.00'), findsOneWidget);
      expect(find.textContaining('Unredacted Content with OTP 654321'), findsOneWidget);
    });

    test('Clearing notifications purges in-memory redacted instances immediately', () async {
      final notif = AppNotification(
        id: 'clear-test',
        packageName: 'com.test',
        title: 'Test',
        content: 'Test content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await controller.generateTestData();
      final notifier = container.read(reviewQueueProvider.notifier);
      notifier.add(notif);

      expect(container.read(reviewQueueProvider), isNotEmpty);

      await controller.clearAll();

      expect(container.read(reviewQueueProvider), isEmpty);
      expect(controller.notifications, isEmpty);
    });
  });
}
