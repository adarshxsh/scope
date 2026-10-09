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

    test('bypasses TFLite model inference and sets modelVersion under low-power mode', () async {
      final notif = AppNotification(
        id: '4',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your verification code is 123456.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isLowPowerMode: true,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.isLowPowerMode, isTrue);
      expect(analyzed.modelVersion, equals('power-save-heuristic-fallback'));
      expect(analyzed.priority, equals('critical'));
      expect(analyzed.extractedFeatures!['otp'], equals('123456'));
      expect(analyzed.latencyMs! < 50, isTrue);
    });

    test('resumes normal model inference when low-power mode is deactivated', () async {
      final lowPowerNotif = AppNotification(
        id: '5',
        packageName: 'com.example.bank',
        title: 'Transaction Alert',
        content: 'Your account has been debited Rs. 5,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isLowPowerMode: true,
      );

      final lowPowerResult = await engine.analyze(lowPowerNotif);
      expect(lowPowerResult.modelVersion, equals('power-save-heuristic-fallback'));

      final normalNotif = lowPowerNotif.copyWith(isLowPowerMode: false);
      final normalResult = await engine.analyze(normalNotif);
      expect(normalResult.modelVersion, isNot(equals('power-save-heuristic-fallback')));
    });
  });
}
