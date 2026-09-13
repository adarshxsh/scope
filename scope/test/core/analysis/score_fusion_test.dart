import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/explanation_generator.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('ScoreFusion Fallback Guardrails', () {
    test('returns unblended rule score when modelResult.isFallback is true', () {
      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_promo_rule',
        category: 'promo',
        priority: 'low',
        matchedSignal: 'keyword match',
      );

      final fallbackModelResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: ['Fallback active'],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: fallbackModelResult,
      );

      expect(fused.isFallback, isTrue);
      expect(fused.score, equals(0.85)); // Authentic rule confidence without blending fallback model score
      expect(fused.category, equals('promo'));
      expect(fused.engineName, contains('model fallback'));
    });

    test('blends scores when modelResult.isFallback is false', () {
      final ruleResult = MatchedRuleResult(
        ruleId: 'custom_promo_rule',
        category: 'promo',
        priority: 'low',
        matchedSignal: 'keyword match',
      );

      final authenticModelResult = AnalysisResult(
        category: 'promo',
        score: 0.95,
        engineName: 'litert_model',
        matchedSignals: ['Authentic prediction'],
        latencyMs: 5,
        isFallback: false,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: authenticModelResult,
      );

      expect(fused.isFallback, isFalse);
      expect(fused.score, equals(0.90)); // Blended boost
      expect(fused.category, equals('promo'));
    });

    test('preserves isFallback status on critical rule bypass', () {
      final ruleResult = MatchedRuleResult(
        ruleId: 'otp_security',
        category: 'sys',
        priority: 'critical',
        matchedSignal: 'otp match',
      );

      final fallbackModelResult = AnalysisResult(
        category: 'sys',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: [],
        latencyMs: 1,
        isFallback: true,
      );

      final fused = ScoreFusion.fuse(
        ruleResult: ruleResult,
        modelResult: fallbackModelResult,
      );

      expect(fused.isFallback, isTrue);
      expect(fused.score, equals(1.0));
    });
  });

  group('ExplanationGenerator Fallback Formatting', () {
    test('renders explicit fallback status when fusedResult.isFallback is true', () {
      final fallbackResult = AnalysisResult(
        category: 'msg',
        score: 0.50,
        engineName: 'litert_model (fallback)',
        matchedSignals: [],
        latencyMs: 1,
        isFallback: true,
      );

      final trace = ExplanationGenerator.generate(
        fusedResult: fallbackResult,
        features: const ExtractedFeatures(),
        priority: 'medium',
      );

      expect(trace, contains('Fallback Heuristic (Model Uninitialized)'));
      expect(trace, isNot(contains('50%')));
    });
  });

  group('AppNotification isFallback Serialization', () {
    test('serializes and deserializes isFallback correctly', () {
      final notif = AppNotification(
        id: 'test-id',
        packageName: 'com.example.app',
        title: 'Title',
        content: 'Content',
        timestamp: 1000000,
        isFallback: true,
      );

      final map = notif.toMap();
      expect(map['isFallback'], isTrue);

      final deserialized = AppNotification.fromMap(map);
      expect(deserialized.isFallback, isTrue);
      expect(deserialized, equals(notif));
    });

    test('copyWith updates isFallback properly', () {
      final notif = AppNotification(
        id: 'test-id',
        packageName: 'com.example.app',
        title: 'Title',
        content: 'Content',
        timestamp: 1000000,
        isFallback: false,
      );

      final updated = notif.copyWith(isFallback: true);
      expect(updated.isFallback, isTrue);
    });
  });
}
