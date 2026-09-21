import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';
import 'package:scope/core/models/notification_model.dart';

class MockInterpreter implements Interpreter {
  bool runCalled = false;

  @override
  void run(Object input, Object output) {
    runCalled = true;
    if (output is List && output.isNotEmpty && output[0] is List) {
      final logitList = output[0] as List;
      if (logitList.length >= 5) {
        logitList[0] = 0.1;
        logitList[1] = 0.1;
        logitList[2] = 0.1;
        logitList[3] = 0.1;
        logitList[4] = 2.5; // Highest logit score for finance category
      }
    }
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    test('halts asset loading and remains in fallback mode when SHA-256 verification fails', () async {
      final classifier = LiteRtClassifier(
        customExpectedHashes: {
          'assets/vocab.txt': '0000000000000000000000000000000000000000000000000000000000000000',
          'assets/model.tflite': '0000000000000000000000000000000000000000000000000000000000000000',
        },
      );

      final notif = AppNotification(
        id: '3',
        packageName: 'com.whatsapp',
        title: 'Tampered Asset Test',
        content: 'Testing invalid SHA-256 hash guard',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isModelLoaded, isFalse);
      expect(result.isFallback, isTrue);
      expect(result.score, equals(0.0));
      expect(result.engineName, contains('fallback'));
    });

    test('executes model inference and sets isFallback to false when valid interpreter is loaded', () async {
      final mockInterpreter = MockInterpreter();
      final mockTokenizer = WordPieceTokenizer.fromLines([
        '[PAD]',
        '[UNK]',
        '[CLS]',
        '[SEP]',
        'bank',
        'alert',
        'account',
        'debited'
      ]);

      final classifier = LiteRtClassifier(
        interpreter: mockInterpreter,
        tokenizer: mockTokenizer,
      );

      final notif = AppNotification(
        id: '4',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account has been debited.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isModelLoaded, isTrue);
      expect(mockInterpreter.runCalled, isTrue);
      expect(result.isFallback, isFalse);
      expect(result.engineName, equals('litert_model'));
      expect(result.category, equals('finance'));
      expect(result.score, greaterThan(0.5));
    });
  });
}
