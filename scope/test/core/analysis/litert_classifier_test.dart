import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';
import 'package:scope/core/models/notification_model.dart';

class FakeInterpreter implements Interpreter {
  final List<double> mockLogits;

  FakeInterpreter({this.mockLogits = const [0.1, 0.2, 0.0, 0.1, 3.0]});

  @override
  void run(Object input, Object output) {
    if (output is List && output.isNotEmpty && output[0] is List) {
      final list = output[0] as List;
      for (int i = 0; i < mockLogits.length && i < list.length; i++) {
        list[i] = mockLogits[i];
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
      
      expect(classifier.isModelLoaded, isFalse);
      expect(result.category, equals('msg'));
      expect(result.engineName, contains('fallback'));
      expect(result.score, equals(0.50));
    });

    test('fallback correctly categorizes bank alerts when model is not loaded', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '2',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(classifier.isModelLoaded, isFalse);
      expect(result.category, equals('finance'));
      expect(result.engineName, contains('fallback'));
      expect(result.score, equals(0.50));
    });

    test('executes neural inference and outputs predicted category with softmax score when model is loaded', () async {
      final mockInterpreter = FakeInterpreter(mockLogits: [0.1, 0.2, 0.0, 0.1, 3.0]);
      final mockTokenizer = WordPieceTokenizer.fromLines(['[PAD]', '[UNK]', '[CLS]', '[SEP]']);
      final classifier = LiteRtClassifier(
        interpreter: mockInterpreter,
        tokenizer: mockTokenizer,
      );

      expect(classifier.isModelLoaded, isTrue);

      final notif = AppNotification(
        id: '3',
        packageName: 'com.example.bank',
        title: 'Account Update',
        content: 'Your transaction was successful.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.engineName, equals('litert_model'));
      expect(result.category, equals('finance')); // Index 4 (highest logit 3.0) corresponds to 'finance'
      expect(result.score, greaterThan(0.40));
      expect(result.score, isNot(equals(0.50)));
      expect(result.matchedSignals.first, contains('Softmax scores'));
    });
  });
}
