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
      expect(result.score, equals(0.0));
      expect(result.isFallback, isTrue);
      expect(classifier.isModelLoaded, isFalse);
      expect(classifier.diagnosticMessage, isNotEmpty);
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
      expect(result.score, equals(0.0));
      expect(result.isFallback, isTrue);
    });

    test('exposes model path and diagnostic information safely', () {
      final classifier = LiteRtClassifier(modelPath: 'assets/non_existent.tflite');
      expect(classifier.modelPath, equals('assets/non_existent.tflite'));
      expect(classifier.isModelLoaded, isFalse);
      expect(classifier.diagnosticMessage, isNotEmpty);
    });

    test('matchedSignals do not expose cleartext personal notification text', () async {
      final classifier = LiteRtClassifier();
      
      final secretContent = 'SUPER_SECRET_OTP_981245';
      final notif = AppNotification(
        id: 'privacy_test_1',
        packageName: 'com.secret.bank',
        title: 'Secret Auth',
        content: secretContent,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      for (final signal in result.matchedSignals) {
        expect(signal.contains(secretContent), isFalse);
      }
    });
  });
}
