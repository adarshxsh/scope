import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/ghost_analysis_engine.dart';
import 'package:scope/core/analysis/thermal_guardrail_service.dart';
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
      GhostAI.instance.clearCache();
      GhostAI.instance.clearLatencyHistory();
      ThermalGuardrailService.instance.reset();
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

    test('tags modelVersion as 1.0.0-tflite-fastpath during thermal throttling or fast-path fallback', () async {
      ThermalGuardrailService.instance.setThermalState(ThermalState.throttled);

      final notif = AppNotification(
        id: '4',
        packageName: 'com.whatsapp',
        title: 'Test Message',
        content: 'Meeting at 5 PM today',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.modelVersion, equals('1.0.0-tflite-fastpath'));
    });
  });
}
