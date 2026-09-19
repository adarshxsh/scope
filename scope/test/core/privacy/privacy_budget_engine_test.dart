import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/privacy/privacy_budget_engine.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/screens/insights_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttentionDatabase db;
  late PrivacyBudgetEngine engine;

  setUp(() async {
    db = AttentionDatabase.inMemory();
    engine = PrivacyBudgetEngine(db: db, defaultTargetEpsilon: 1.0);
    await engine.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  group('PrivacyBudgetEngine Unit Tests', () {
    test('initializes with default target budget and 0 consumed budget', () {
      expect(engine.targetEpsilon, 1.0);
      expect(engine.consumedEpsilon, 0.0);
      expect(engine.remainingBudget, 1.0);
      expect(engine.isBudgetDepleted, isFalse);
    });

    test('clips values correctly to min/max sensitivity bounds', () {
      expect(engine.clip(150.0, 0.0, 100.0), 100.0);
      expect(engine.clip(-10.0, 0.0, 100.0), 0.0);
      expect(engine.clip(42.0, 0.0, 100.0), 42.0);

      expect(engine.clipInt(150, 0, 100), 100);
      expect(engine.clipInt(-10, 0, 100), 0);
      expect(engine.clipInt(42, 0, 100), 42);
    });

    test('samples Laplace noise calibrated to sensitivity / epsilon', () {
      final noiseList = <double>[];
      for (int i = 0; i < 100; i++) {
        final n = engine.sampleLaplace(1.0, 0.1);
        noiseList.add(n);
      }
      expect(noiseList.length, 100);
      expect(noiseList.any((n) => n != 0.0), isTrue);
    });

    test('deducts epsilon query from privacy budget atomically', () async {
      expect(engine.remainingBudget, 1.0);

      final res = await engine.evaluateIntQuery(
        rawValue: 10,
        sensitivity: 1.0,
        epsilonQuery: 0.2,
      );

      expect(res.isFallback, isFalse);
      expect(engine.consumedEpsilon, closeTo(0.2, 0.001));
      expect(engine.remainingBudget, closeTo(0.8, 0.001));
    });

    test('persists budget entries in Drift database across calls', () async {
      await engine.evaluateDoubleQuery(
        rawValue: 50.0,
        sensitivity: 1.0,
        epsilonQuery: 0.3,
      );

      final today = engine.currentEpochDate;
      final entry = await db.privacyBudgetDao.getBudgetForDate(today);

      expect(entry, isNotNull);
      expect(entry!.consumedEpsilon, closeTo(0.3, 0.001));
      expect(entry.targetEpsilon, 1.0);

      final newEngine = PrivacyBudgetEngine(db: db);
      await newEngine.initialize();
      expect(newEngine.consumedEpsilon, closeTo(0.3, 0.001));
    });

    test('degrades gracefully to coarsened bucket intervals when budget is depleted', () async {
      await engine.evaluateDoubleQuery(
        rawValue: 10.0,
        sensitivity: 1.0,
        epsilonQuery: 1.0,
      );

      expect(engine.isBudgetDepleted, isTrue);

      final res = await engine.evaluateIntQuery(
        rawValue: 17,
        sensitivity: 1.0,
        epsilonQuery: 0.1,
      );

      expect(res.isFallback, isTrue);
      expect(res.bucketInterval, '10–25');
      expect(res.value, 15);
    });
  });

  group('DAO Budget-Aware Aggregate Query Tests', () {
    test('FocusSessionDao getBudgetAwareAggregateStats deducts budget and injects noise', () async {
      await db.focusSessionDao.insertSession(FocusSessionEntry(
        id: 0,
        sessionStart: DateTime.now(),
        sessionEnd: DateTime.now().add(const Duration(minutes: 30)),
        interruptions: 3,
        completion: true,
        duration: 1800,
      ));

      final result = await db.focusSessionDao.getBudgetAwareAggregateStats(engine, epsilonQuery: 0.2);

      expect(result.value.sessionCount, 1);
      expect(result.value.totalDurationSeconds, greaterThanOrEqualTo(0));
      expect(result.value.totalInterruptions, greaterThanOrEqualTo(0));
      expect(engine.consumedEpsilon, closeTo(0.2, 0.001));
    });

    test('DailyBriefDao getBudgetAwareBriefForDate deducts budget and returns noisy brief', () async {
      const dateStr = '2026-09-09';
      await db.dailyBriefDao.incrementStats(dateStr, reviewed: 12, completed: 5);

      final result = await db.dailyBriefDao.getBudgetAwareBriefForDate(dateStr, engine, epsilonQuery: 0.2);

      expect(result.value.date, dateStr);
      expect(result.value.notificationsReviewed, greaterThanOrEqualTo(0));
      expect(result.value.actionsCompleted, greaterThanOrEqualTo(0));
      expect(engine.consumedEpsilon, closeTo(0.2, 0.001));
    });
  });

  group('NotificationController Privacy Budget Integration Tests', () {
    test('NotificationController delegates telemetry queries through PrivacyBudgetEngine', () async {
      final controller = NotificationController(
        privacyBudgetEngine: engine,
      );

      final priorityRes = await controller.getNoisyPriorityDistribution(epsilonQuery: 0.1);
      expect(priorityRes.value, contains('critical'));
      expect(engine.consumedEpsilon, closeTo(0.1, 0.001));

      final hourlyRes = await controller.getNoisyHourlyVolume(epsilonQuery: 0.1);
      expect(hourlyRes.value.length, 24);
      expect(engine.consumedEpsilon, closeTo(0.2, 0.001));

      final overviewRes = await controller.getNoisyOverviewMetrics(epsilonQuery: 0.1);
      expect(overviewRes.value, contains('totalCaptured'));
      expect(engine.consumedEpsilon, closeTo(0.3, 0.001));

      controller.dispose();
    });
  });

  group('InsightsScreen Widget Tests', () {
    testWidgets('renders Privacy Budget Guard banner and insights', (WidgetTester tester) async {
      final controller = NotificationController(
        privacyBudgetEngine: engine,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InsightsScreen(controller: controller),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Budget Guard Active'), findsOneWidget);
      expect(find.text('Priority Distribution'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Analysis Overview'),
        200.0,
        scrollable: find.byType(Scrollable),
      );

      expect(find.text('Hourly Volume'), findsOneWidget);
      expect(find.text('Analysis Overview'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('displays budget depleted fallback banner when epsilon budget is exhausted', (WidgetTester tester) async {
      await engine.evaluateDoubleQuery(rawValue: 1.0, sensitivity: 1.0, epsilonQuery: 1.0);

      final controller = NotificationController(
        privacyBudgetEngine: engine,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InsightsScreen(controller: controller),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Privacy Budget Depleted (Coarsened Fallback Active)'), findsOneWidget);

      controller.dispose();
    });
  });
}
