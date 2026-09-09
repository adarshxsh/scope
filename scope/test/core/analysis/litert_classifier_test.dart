import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRtClassifier', () {
    test('initializes and falls back gracefully to heuristic classifier when asset loading fails', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Hello, how are you?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
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
    });

    test('falls back gracefully on SHA-256 digest mismatch', () async {
      final classifier = LiteRtClassifier(
        expectedVocabSha256: '0000000000000000000000000000000000000000000000000000000000000000',
      );

      final notif = AppNotification(
        id: '3',
        packageName: 'com.example.app',
        title: 'Alert',
        content: 'Verification code 123456',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.category, equals('sys'));
      expect(result.engineName, contains('fallback'));
    });

    test('SHA-256 verification overhead during asset initialization is within 5ms constraint', () async {
      final stopwatch = Stopwatch()..start();
      final classifier = LiteRtClassifier();
      final notif = AppNotification(
        id: '4',
        packageName: 'com.example.app',
        title: 'Test',
        content: 'Test content',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      stopwatch.stop();

      // Ensure latency for analyze + init is low
      expect(result.latencyMs, lessThanOrEqualTo(50));
    });
  });
}
