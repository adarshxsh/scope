import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

class FakeInterpreter implements Interpreter {
  final List<double> logitsToReturn;

  FakeInterpreter({required this.logitsToReturn});

  @override
  void run(Object input, Object output) {
    if (output is List && output.isNotEmpty && output[0] is List) {
      final outList = output[0] as List;
      for (int i = 0; i < logitsToReturn.length && i < outList.length; i++) {
        outList[i] = logitsToReturn[i];
      }
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

    test('executes active TFLite interpreter model inference and computes softmax category scores', () async {
      // Logits corresponding to categories: ['promo', 'social', 'sys', 'msg', 'finance']
      // Index 4 (finance) has highest logit 5.0
      final fakeInterpreter = FakeInterpreter(
        logitsToReturn: [0.5, 0.1, 0.2, 0.1, 5.0],
      );

      final classifier = LiteRtClassifier(interpreter: fakeInterpreter);
      expect(classifier.isModelLoaded, isTrue);

      final notif = AppNotification(
        id: '3',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.engineName, equals('litert_model'));
      expect(result.category, equals('finance'));
      expect(result.score, greaterThan(0.90));
      expect(result.matchedSignals.first, contains('Softmax scores'));
    });

    test('active model inference predicts promo category when promo logit is highest', () async {
      // Index 0 (promo) has highest logit 6.0
      final fakeInterpreter = FakeInterpreter(
        logitsToReturn: [6.0, 0.1, 0.2, 0.1, 0.5],
      );

      final classifier = LiteRtClassifier(interpreter: fakeInterpreter);

      final notif = AppNotification(
        id: '4',
        packageName: 'com.shopping.app',
        title: 'Mega Discount',
        content: 'Get 50% off on all items today!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.engineName, equals('litert_model'));
      expect(result.category, equals('promo'));
      expect(result.score, greaterThan(0.90));
    });
  });
}
