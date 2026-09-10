import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/screens/diagnostic_screen.dart';

class FakeFallbackGhostAnalysisEngine extends GhostAnalysisEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<AppNotification> analyze(AppNotification notification) async {
    return notification.copyWith(
      priority: 'medium',
      priorityScore: 0.0,
      classifiedCategory: 'msg',
      explanation: 'Fallback heuristic active.',
      latencyMs: 1,
      isFallback: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Inference Fallback Metadata & Confidence Tests', () {
    test('LiteRtClassifier returns isFallback = true and confidence = 0.0 during uninitialized / fallback states', () async {
      final classifier = LiteRtClassifier();
      final notif = AppNotification(
        id: 'test_1',
        packageName: 'com.example.app',
        title: 'Test Title',
        content: 'Test Body',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.isFallback, isTrue);
      expect(result.confidence, equals(0.0));
      expect(result.score, equals(0.0));
    });

    test('GhostAI returns isFallback = true and confidence = 0.0 when model is not loaded', () async {
      final notif = AppNotification(
        id: 'test_2',
        packageName: 'com.whatsapp',
        title: 'WhatsApp Message',
        content: 'Hello there',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);

      expect(result.isFallback, isTrue);
      expect(result.confidence, equals(0.0));
    });

    test('ScoreFusion bypasses hybrid blending when modelResult.isFallback is true', () {
      final fallbackModelResult = AnalysisResult(
        category: 'msg',
        score: 0.0,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback active'],
        latencyMs: 1,
        isFallback: true,
      );

      final ruleResult = MatchedRuleResult(
        ruleId: 'test_rule',
        category: 'finance',
        priority: 'high',
        matchedSignal: 'keyword: bill',
      );

      // ScoreFusion with fallback modelResult and a matched rule
      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: fallbackModelResult,
      );

      expect(fused.isFallback, isFalse);
      expect(fused.category, equals('finance'));
      expect(fused.score, equals(0.85)); // Base rule score without dilution
      expect(fused.engineName, contains('model fallback'));

      // ScoreFusion with fallback modelResult and NO rule
      final fusedNoRule = ScoreFusion.fuse(
        ruleResult: null,
        modelResult: fallbackModelResult,
      );

      expect(fusedNoRule.isFallback, isTrue);
      expect(fusedNoRule.score, equals(0.0));
    });

    test('GhostAnalysisEngine forwards isFallback status to AppNotification', () async {
      final engine = GhostAnalysisEngine();
      final notif = AppNotification(
        id: 'test_3',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Call me back',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.isFallback, isTrue);
      expect(analyzed.modelVersion, contains('fallback'));
    });

    testWidgets('DiagnosticScreen displays fallback warning badge when isFallback is true', (WidgetTester tester) async {
      final engine = FakeFallbackGhostAnalysisEngine();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticScreen(engine: engine),
          ),
        ),
      );

      // Fill in input fields
      final contentFieldFinder = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == 'Content Body',
      );
      await tester.enterText(contentFieldFinder, 'Test fallback warning display');

      // Click analyze
      await tester.tap(find.text('ANALYZE NOTIFICATION'));
      await tester.pumpAndSettle();

      // Verify explicit fallback warning appears
      expect(find.text('HEURISTIC FALLBACK ACTIVE'), findsOneWidget);
      expect(find.textContaining('Confidence Score: 0% (Fallback Mode)'), findsOneWidget);
    });
  });
}
