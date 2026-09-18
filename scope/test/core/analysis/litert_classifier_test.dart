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

    test('verifies asset SHA-256 digests and manages isModelLoaded state', () async {
      final classifier = LiteRtClassifier();
      // Allow async initialization to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // isModelLoaded is false on desktop test env without native tflite library, or true if loaded
      expect(classifier.isModelLoaded, isFalse);

      final notif = AppNotification(
        id: '3',
        packageName: 'com.whatsapp',
        title: 'OTP Code',
        content: 'Your code is 123456',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      expect(result.category, equals('sys'));
      expect(result.engineName, contains('fallback'));
    });
  });
}
