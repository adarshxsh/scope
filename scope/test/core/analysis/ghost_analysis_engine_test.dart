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
      // Verify PII redaction on content
      expect(analyzed.content, contains('[REDACTED_AMOUNT]'));
      expect(analyzed.content, isNot(contains('Rs. 5,000')));
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
      // Verify PII redaction on content
      expect(analyzed.content, contains('[REDACTED_OTP]'));
      expect(analyzed.content, isNot(contains('882715')));
    });

    test('sanitizes multiple PII tokens in title and content while preserving analysis', () async {
      final notif = AppNotification(
        id: 'pii-test',
        packageName: 'com.bank.app',
        title: 'Alert for user@test.com',
        content: r'Card 4532110088902311 debited $150.50. OTP 123456. Call 800-555-0199.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.title, contains('[REDACTED_EMAIL]'));
      expect(analyzed.title, isNot(contains('user@test.com')));
      expect(analyzed.content, contains('[REDACTED_CARD]'));
      expect(analyzed.content, contains('[REDACTED_AMOUNT]'));
      expect(analyzed.content, contains('[REDACTED_OTP]'));
      expect(analyzed.content, contains('[REDACTED_PHONE]'));
      expect(analyzed.content, isNot(contains('4532110088902311')));
      expect(analyzed.content, isNot(contains('123456')));
      expect(analyzed.content, isNot(contains('800-555-0199')));
      expect(analyzed.extractedFeatures!['amount'], equals(150.50));
      expect(analyzed.extractedFeatures!['otp'], equals('123456'));
    });

    test('sanitizes title and content on status or progress notification early exit', () async {
      final notif = AppNotification(
        id: 'status-test',
        packageName: 'com.app',
        title: 'Downloading file for user@test.com',
        content: 'Downloading file transfer with passcode 882715',
        category: 'progress',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final analyzed = await engine.analyze(notif);

      expect(analyzed.priority, equals('low'));
      expect(analyzed.classifiedCategory, equals('system_status'));
      expect(analyzed.title, contains('[REDACTED_EMAIL]'));
      expect(analyzed.content, contains('[REDACTED_OTP]'));
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
  });
}
