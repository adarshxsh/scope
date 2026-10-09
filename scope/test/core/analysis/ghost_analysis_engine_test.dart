import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GhostAnalysisEngine', () {
    const String sampleJson = '''
    {
      "version": "1.0",
      "rules": [
        {
          "id": "bank_debit",
          "category": "finance",
          "priority": "critical",
          "conditions": {
            "keywords": ["debited", "spent"]
          }
        }
      ]
    }
    ''';

    late GhostAnalysisEngine engine;

    setUp(() {
      engine = GhostAnalysisEngine();
      engine.ruleEngine.compile(sampleJson);
    });

    test('orchestrates pipeline and classifies bank debit notification as critical', () async {
      final notif = AppNotification(
        id: '1',
        packageName: 'com.example.bank',
        title: 'Transaction Alert',
        content: 'Your account has been debited Rs. 5,000 for your premium purchase.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.priority, equals('critical'));
      expect(analyzed.classifiedCategory, equals('finance'));
      expect(analyzed.explanation, contains('Amount: Found transaction amount'));
      expect(analyzed.latencyMs, isNotNull);
      expect(analyzed.extractedFeatures, isNotNull);
      expect(analyzed.extractedFeatures!['amount'], equals(5000.0));
    });

    test('orchestrates pipeline and classifies OTP messages as critical priority', () async {
      final notif = AppNotification(
        id: '2',
        packageName: 'com.whatsapp',
        title: 'WhatsApp verification',
        content: 'Your registration code is 882715.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.priority, equals('critical'));
      expect(analyzed.extractedFeatures!['otp'], equals('882715'));
    });

    test('categorizes low priority promo keywords as low', () async {
      final notif = AppNotification(
        id: '3',
        packageName: 'com.amazon',
        title: 'Deals of the day',
        content: 'Get 25% off on shoes. Buy today!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.priority, equals('low'));
      expect(analyzed.classifiedCategory, equals('promo'));
    });

    test('uses LRU cache for duplicate analyze calls meeting sub-50ms benchmark', () async {
      final notif = AppNotification(
        id: 'cache_test_1',
        packageName: 'com.test.app',
        title: 'Duplicate Title',
        content: 'Duplicate content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final firstPass = await engine.analyze(notif);
      expect(firstPass.latencyMs, isNotNull);

      final secondPass = await engine.analyze(notif);
      expect(secondPass.priority, equals(firstPass.priority));
      expect(secondPass.latencyMs, lessThan(50));
    });

    test('clears LRU cache on demand', () async {
      final notif = AppNotification(
        id: 'cache_clear_1',
        packageName: 'com.test.app',
        title: 'Title',
        content: 'Content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await engine.analyze(notif);
      engine.clearCache();
      // Should re-analyze without error
      final reAnalyzed = await engine.analyze(notif);
      expect(reAnalyzed.id, equals('cache_clear_1'));
    });
  });
}
