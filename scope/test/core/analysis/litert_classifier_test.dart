import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class FakeInterpreter implements Interpreter {
  @override
  void run(Object input, Object output) {
    if (output is List && output.isNotEmpty && output[0] is List) {
      final outList = output[0] as List;
      // Category logits: ['promo', 'social', 'sys', 'msg', 'finance']
      outList[0] = 0.1;
      outList[1] = 0.1;
      outList[2] = 0.1;
      outList[3] = 0.1;
      outList[4] = 0.8; // finance
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

    test('detects SHA-256 model hash mismatch and triggers integrity alert fallback', () async {
      final classifier = LiteRtClassifier(
        expectedModelHash: 'bad0000000000000000000000000000000000000000000000000000000000000',
      );

      final notif = AppNotification(
        id: '3',
        packageName: 'com.example.app',
        title: 'Promo',
        content: '50% off discount sale today',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isIntegrityViolation, isTrue);
      expect(classifier.isModelLoaded, isFalse);
      expect(result.engineName, equals('litert_model (fallback - integrity alert)'));
      expect(result.category, equals('promo'));
      expect(result.score, equals(0.0));
      expect(result.isFallback, isTrue);
    });

    test('detects SHA-256 vocab hash mismatch and triggers integrity alert fallback', () async {
      final classifier = LiteRtClassifier(
        expectedVocabHash: 'bad0000000000000000000000000000000000000000000000000000000000000',
      );

      final notif = AppNotification(
        id: '4',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isIntegrityViolation, isTrue);
      expect(classifier.isModelLoaded, isFalse);
      expect(result.engineName, equals('litert_model (fallback - integrity alert)'));
      expect(result.category, equals('finance'));
      expect(result.score, equals(0.0));
      expect(result.isFallback, isTrue);
    });

    test('executes model inference with engineName litert_model when SHA-256 verification succeeds', () async {
      final fakeInterpreter = FakeInterpreter();
      final classifier = LiteRtClassifier(
        interpreter: fakeInterpreter,
      );

      final notif = AppNotification(
        id: '5',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isIntegrityViolation, isFalse);
      expect(classifier.isModelLoaded, isTrue);
      expect(result.engineName, equals('litert_model'));
      expect(result.category, equals('finance'));
      expect(result.score, greaterThan(0.3));
      expect(result.isFallback, isFalse);
    });
  });
}

