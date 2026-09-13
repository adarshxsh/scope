import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/score_fusion.dart';
import 'package:scope/core/analysis/rule_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRtClassifier', () {
    test('initializes and falls back gracefully to heuristic classifier when asset loading fails on desktop test runner', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Hello, how are you?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(classifier.isModelLoaded, isFalse);
      expect(result.category, equals('msg'));
      expect(result.engineName, contains('fallback'));
      expect(result.score, equals(0.50));
    });

    test('fallback correctly categorizes bank alerts', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '2',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('finance'));
      expect(result.engineName, contains('fallback'));
      expect(result.score, equals(0.50));
    });

    test('executes model inference and outputs softmax predictions when interpreter is loaded', () async {
      // Mock interpreter logits output for finance category (index 4)
      final classifier = LiteRtClassifier(
        interpreterRunner: (input, output) {
          final outList = output as List;
          // Set logits: promo: 0.1, social: 0.2, sys: 0.1, msg: 0.5, finance: 5.0
          outList[0] = [0.1, 0.2, 0.1, 0.5, 5.0];
        },
      );

      expect(classifier.isModelLoaded, isTrue);

      final notif = AppNotification(
        id: '3',
        packageName: 'com.hfdc.bank',
        title: 'Bank Transaction',
        content: 'Your card ending 4012 was charged Rs 1,500.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.category, equals('finance'));
      expect(result.engineName, equals('litert_model'));
      expect(result.score, greaterThan(0.90)); // Softmax confidence should be high
      expect(result.matchedSignals.first, contains('Softmax scores'));
    });

    test('correctly predicts promo category based on model logits', () async {
      final classifier = LiteRtClassifier(
        interpreterRunner: (input, output) {
          final outList = output as List;
          // Set logits: promo: 6.0, social: 0.1, sys: 0.0, msg: 0.2, finance: 0.1
          outList[0] = [6.0, 0.1, 0.0, 0.2, 0.1];
        },
      );

      final notif = AppNotification(
        id: '4',
        packageName: 'com.amazon.shopping',
        title: 'Flash Sale',
        content: 'Get 50% off on all electronics today!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.category, equals('promo'));
      expect(result.engineName, equals('litert_model'));
      expect(result.score, greaterThan(0.95));
    });

    test('falls back gracefully on inference exception', () async {
      final classifier = LiteRtClassifier(
        interpreterRunner: (input, output) {
          throw Exception('TFLite tensor evaluation error');
        },
      );

      final notif = AppNotification(
        id: '5',
        packageName: 'com.example.app',
        title: 'Test Title',
        content: 'Test content for error handling',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.engineName, contains('fallback on error'));
      expect(result.score, equals(0.50));
      expect(result.matchedSignals.first, contains('Inference error'));
    });

    test('ScoreFusion receives dynamic confidence score from LiteRtClassifier', () async {
      final classifier = LiteRtClassifier(
        interpreterRunner: (input, output) {
          final outList = output as List;
          // Set logits: promo: 0.1, social: 0.1, sys: 0.1, msg: 4.0, finance: 0.1
          outList[0] = [0.1, 0.1, 0.1, 4.0, 0.1];
        },
      );

      final notif = AppNotification(
        id: '6',
        packageName: 'com.whatsapp',
        title: 'Alice',
        content: 'Are we still meeting for lunch?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final modelResult = await classifier.analyze(notif);
      expect(modelResult.score, greaterThan(0.90));

      final matchedRule = MatchedRuleResult(
        ruleId: 'msg_rule',
        category: 'msg',
        matchedSignal: 'Messenger keyword match',
        priority: 'high',
      );

      final fused = ScoreFusion.fuse(
        ruleResult: matchedRule,
        modelResult: modelResult,
      );

      // Hybrid score should boost based on high dynamic model confidence score (>0.90)
      expect(fused.score, greaterThanOrEqualTo(0.85));
      expect(fused.category, equals('msg'));
      expect(fused.engineName, contains('score_fusion'));
    });
  });
}
