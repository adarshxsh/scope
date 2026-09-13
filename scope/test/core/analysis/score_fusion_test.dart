import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/analysis/score_fusion.dart';

void main() {
  group('ScoreFusion & Platt Confidence Calibration', () {
    tearDown(() {
      ScoreFusion.resetConfig();
    });

    group('CategoryPrecision & CategoryPrecisionMapping', () {
      test('provides correct default precision weights and Platt parameters', () {
        final mapping = CategoryPrecisionMapping();

        final finance = mapping.getPrecision('finance');
        expect(finance.alpha, equals(0.90));
        expect(finance.plattA, equals(3.0));
        expect(finance.plattB, equals(-0.2));

        final promo = mapping.getPrecision('promo');
        expect(promo.alpha, equals(0.35));
        expect(promo.plattA, equals(2.0));
        expect(promo.plattB, equals(-1.5));

        final unknown = mapping.getPrecision('unknown_category');
        expect(unknown.alpha, equals(0.50));
      });

      test('parses dynamic runtime JSON calibration configuration map', () {
        final jsonConfig = {
          'finance': {'alpha': 0.95, 'a': 4.0, 'b': -0.1},
          'promo': {'alpha': 0.20, 'a': 1.5, 'b': -2.0},
        };

        final mapping = CategoryPrecisionMapping.fromMap(jsonConfig);

        expect(mapping.getPrecision('finance').alpha, equals(0.95));
        expect(mapping.getPrecision('finance').plattA, equals(4.0));
        expect(mapping.getPrecision('promo').alpha, equals(0.20));
      });
    });

    group('Platt Sigmoidal Transformation', () {
      test('calibrates raw model score using sigmoidal transformation sigma(A * x + B)', () {
        const precision = CategoryPrecision(alpha: 0.90, plattA: 3.0, plattB: -0.2);
        // z = 3.0 * 0.90 - 0.2 = 2.5
        // sigma(2.5) = 1 / (1 + exp(-2.5)) ~ 0.92414
        final calibrated = precision.calibrate(0.90);
        expect(calibrated, closeTo(0.9241, 0.001));
      });

      test('ScoreFusion.calibrateModelScore uses category Platt parameters', () {
        final calibratedFinance = ScoreFusion.calibrateModelScore(0.95, 'finance');
        // z = 3.0 * 0.95 - 0.2 = 2.65 => sigma(2.65) ~ 0.934
        expect(calibratedFinance, closeTo(0.934, 0.01));
      });
    });

    group('Deterministic Critical Security Bypasses', () {
      test('otp_security rule match bypasses fusion and returns score 1.0', () {
        const ruleMatch = MatchedRuleResult(
          ruleId: 'otp_security',
          category: 'sys',
          priority: 'critical',
          matchedSignal: 'Content matches "otp"',
        );

        const modelResult = AnalysisResult(
          category: 'promo',
          score: 0.10,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(
          ruleResult: ruleMatch,
          modelResult: modelResult,
        );

        expect(result.score, equals(1.0));
        expect(result.category, equals('sys'));
        expect(result.engineName, contains('rule bypass: otp_security'));
      });

      test('finance_debit rule match bypasses fusion and returns score 1.0', () {
        const ruleMatch = MatchedRuleResult(
          ruleId: 'finance_debit',
          category: 'finance',
          priority: 'critical',
          matchedSignal: 'Title matches "bank"',
        );

        const modelResult = AnalysisResult(
          category: 'sys',
          score: 0.20,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(
          ruleResult: ruleMatch,
          modelResult: modelResult,
        );

        expect(result.score, equals(1.0));
        expect(result.category, equals('finance'));
        expect(result.engineName, contains('rule bypass: finance_debit'));
      });

      test('scholarship_portal rule match bypasses fusion and returns score 1.0', () {
        const ruleMatch = MatchedRuleResult(
          ruleId: 'scholarship_portal',
          category: 'scholarship',
          priority: 'critical',
          matchedSignal: 'Package matched (in.gov.scholarships)',
        );

        const modelResult = AnalysisResult(
          category: 'social',
          score: 0.05,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(
          ruleResult: ruleMatch,
          modelResult: modelResult,
        );

        expect(result.score, equals(1.0));
        expect(result.category, equals('scholarship'));
        expect(result.engineName, contains('rule bypass: scholarship_portal'));
      });

      test('any rule with priority critical returns score 1.0', () {
        const ruleMatch = MatchedRuleResult(
          ruleId: 'custom_critical',
          category: 'health',
          priority: 'critical',
          matchedSignal: 'Emergency signal',
        );

        const modelResult = AnalysisResult(
          category: 'health',
          score: 0.30,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(
          ruleResult: ruleMatch,
          modelResult: modelResult,
        );

        expect(result.score, equals(1.0));
      });
    });

    group('Dynamic Category Precision Fusion', () {
      test('high-precision financial alert gives high model weight (alpha = 0.90)', () {
        const ruleMatch = MatchedRuleResult(
          ruleId: 'finance_alert',
          category: 'finance',
          priority: 'high',
          matchedSignal: 'Content matches "payment"',
        );

        const modelResult = AnalysisResult(
          category: 'finance',
          score: 0.95,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(
          ruleResult: ruleMatch,
          modelResult: modelResult,
        );

        // calibrated model score for 0.95 ~ 0.934
        // S_rule for high = 0.85
        // S_fused = 0.90 * 0.934 + 0.10 * 0.85 = 0.8406 + 0.085 = 0.9256
        expect(result.score, closeTo(0.925, 0.02));
        expect(result.category, equals('finance'));
        expect(result.matchedSignals, anyElement(contains('(alpha): 0.90')));
      });

      test('low-precision promo alert gives lower model weight (alpha = 0.35)', () {
        const ruleMatch = MatchedRuleResult(
          ruleId: 'promo_deals',
          category: 'promo',
          priority: 'low',
          matchedSignal: 'Content matches "sale"',
        );

        const modelResult = AnalysisResult(
          category: 'promo',
          score: 0.70,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(
          ruleResult: ruleMatch,
          modelResult: modelResult,
        );

        // calibrated model score for promo 0.70 (z = 2.0*0.70 - 1.5 = -0.1 => sigma(-0.1) ~ 0.475)
        // S_rule for low = 0.15
        // S_fused = 0.35 * 0.475 + 0.65 * 0.15 = 0.166 + 0.0975 = 0.2638
        expect(result.score, closeTo(0.264, 0.02));
        expect(result.matchedSignals, anyElement(contains('(alpha): 0.35')));
      });

      test('calibrates model prediction when ruleResult is null', () {
        const modelResult = AnalysisResult(
          category: 'finance',
          score: 0.90,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(
          ruleResult: null,
          modelResult: modelResult,
        );

        // Platt calibration for finance 0.90 => z = 3*0.9 - 0.2 = 2.5 => sigma(2.5) ~ 0.924
        expect(result.score, closeTo(0.924, 0.01));
        expect(result.category, equals('finance'));
      });
    });

    group('Runtime Configuration Loading', () {
      test('updates ScoreFusion active mapping when configured from map', () {
        ScoreFusion.configureFromMap({
          'finance': {'alpha': 0.99, 'a': 5.0, 'b': 0.0},
        });

        expect(ScoreFusion.activeMapping.getPrecision('finance').alpha, equals(0.99));

        const modelResult = AnalysisResult(
          category: 'finance',
          score: 0.80,
          engineName: 'ml',
          matchedSignals: [],
          latencyMs: 1,
        );

        final result = ScoreFusion.fuse(ruleResult: null, modelResult: modelResult);
        // z = 5.0 * 0.8 = 4.0 => sigma(4.0) ~ 0.982
        expect(result.score, closeTo(0.982, 0.01));
      });
    });
  });
}
