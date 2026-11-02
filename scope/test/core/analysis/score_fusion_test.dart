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
        expect(finance.plattA, equals(1.2));
        expect(finance.plattB, equals(0.3));

        final promo = mapping.getPrecision('promo');
        expect(promo.alpha, equals(0.35));
        expect(promo.plattA, equals(0.8));
        expect(promo.plattB, equals(-0.5));

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
      test('calibrates raw model score using sigmoidal transformation on logit', () {
        const precision = CategoryPrecision(alpha: 0.90, plattA: 1.2, plattB: 0.3);
        // raw = 0.90 => logit(0.90) = ln(0.9/0.1) = ln(9) ~ 2.1972
        // z = 1.2 * 2.1972 + 0.3 = 2.9366
        // sigma(2.9366) = 1 / (1 + exp(-2.9366)) ~ 0.9496
        final calibrated = precision.calibrate(0.90);
        expect(calibrated, closeTo(0.9496, 0.001));
      });

      test('ScoreFusion.calibrateModelScore uses category Platt parameters', () {
        final calibratedFinance = ScoreFusion.calibrateModelScore(0.95, 'finance');
        // raw = 0.95 => logit(0.95) = ln(19) ~ 2.9444
        // z = 1.2 * 2.9444 + 0.3 = 3.833
        // sigma(3.833) ~ 0.9789
        expect(calibratedFinance, closeTo(0.9789, 0.01));
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
        expect(result.isFallback, isFalse);
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
        expect(result.isFallback, isFalse);
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
        expect(result.isFallback, isFalse);
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
        expect(result.isFallback, isFalse);
      });
    });

    group('Fallback Model Handling', () {
      test('fallback model result does NOT blend score into rule match result', () {
        final rule = MatchedRuleResult(
          ruleId: 'custom_rule_2',
          category: 'finance',
          priority: 'high',
          matchedSignal: 'Matched finance keyword',
        );

        final fallbackModelResult = AnalysisResult(
          category: 'finance',
          score: 0.0,
          engineName: 'litert_model (fallback)',
          matchedSignals: ['Uninitialized model'],
          latencyMs: 1,
          isFallback: true,
        );

        final fused = ScoreFusion.fuse(
          ruleResult: rule,
          modelResult: fallbackModelResult,
        );

        expect(fused.category, equals('finance'));
        expect(fused.score, equals(0.85)); // Rule baseline preserved without blending 0.0 fallback score
        expect(fused.engineName, contains('rule only, ml fallback'));
        expect(fused.isFallback, isFalse);
      });

      test('fallback model result returned directly when no rule matches', () {
        final fallbackModelResult = AnalysisResult(
          category: 'msg',
          score: 0.0,
          engineName: 'litert_model (fallback)',
          matchedSignals: ['Uninitialized model'],
          latencyMs: 1,
          isFallback: true,
        );

        final fused = ScoreFusion.fuse(
          ruleResult: null,
          modelResult: fallbackModelResult,
        );

        expect(fused.category, equals('msg'));
        expect(fused.score, equals(0.0));
        expect(fused.engineName, equals('litert_model (fallback)'));
        expect(fused.isFallback, isTrue);
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

        // raw = 0.95 => logit(0.95) ~ 2.9444 => z = 1.2*2.9444 + 0.3 = 3.833 => calibrated ~ 0.9789
        // S_rule for high = 0.85
        // S_fused = 0.90 * 0.9789 + 0.10 * 0.85 = 0.8810 + 0.085 = 0.9660
        expect(result.score, closeTo(0.966, 0.02));
        expect(result.category, equals('finance'));
        expect(result.matchedSignals, anyElement(contains('(alpha): 0.90')));
        expect(result.isFallback, isFalse);
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

        // promo: alpha=0.35, plattA=0.8, plattB=-0.5
        // raw = 0.70 => logit(0.70) = ln(0.7/0.3) = ln(2.333) ~ 0.8473
        // z = 0.8 * 0.8473 - 0.5 = 0.1778
        // sigma(0.1778) = 1 / (1 + exp(-0.1778)) ~ 0.5443
        // S_rule for low = 0.15
        // S_fused = 0.35 * 0.5443 + 0.65 * 0.15 = 0.1905 + 0.0975 = 0.2880
        expect(result.score, closeTo(0.288, 0.02));
        expect(result.matchedSignals, anyElement(contains('(alpha): 0.35')));
        expect(result.isFallback, isFalse);
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

        // raw = 0.90 => logit(0.90) ~ 2.1972 => z = 1.2*2.1972 + 0.3 = 2.9366 => sigma(2.9366) ~ 0.9496
        expect(result.score, closeTo(0.9496, 0.01));
        expect(result.category, equals('finance'));
        expect(result.isFallback, isFalse);
      });
    });

    group('Runtime Configuration Loading', () {
      test('updates ScoreFusion active mapping when configured from map', () {
        ScoreFusion.configureFromMap({
          'finance': {'alpha': 0.99, 'a': 2.0, 'b': 0.0},
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
        // raw = 0.80 => logit(0.80) ~ 1.3863 => z = 2.0 * 1.3863 = 2.7726 => sigma(2.7726) ~ 0.9411
        expect(result.score, closeTo(0.9411, 0.01));
        expect(result.isFallback, isFalse);
      });
    });
  });
}
