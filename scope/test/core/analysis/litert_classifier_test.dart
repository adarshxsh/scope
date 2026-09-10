import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

class MockCategoryInterpreter implements Interpreter {
  bool runCalled = false;
  List<double> mockOutputs = [0.1, 0.1, 0.1, 0.1, 5.0]; // finance highest logit (index 4)

  @override
  void run(Object input, Object output) {
    runCalled = true;
    if (output is List && output.isNotEmpty && output[0] is List) {
      final outList = output[0] as List;
      for (int i = 0; i < mockOutputs.length && i < outList.length; i++) {
        outList[i] = mockOutputs[i];
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRtClassifier', () {
    test('executes active neural model inference when model is loaded', () async {
      final mockInterpreter = MockCategoryInterpreter();
      final classifier = LiteRtClassifier(interpreter: mockInterpreter);

      expect(classifier.isModelLoaded, isTrue);

      final notif = AppNotification(
        id: '1',
        packageName: 'com.example.app',
        title: 'Account Update',
        content: 'Your account balance is updated.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(mockInterpreter.runCalled, isTrue);
      expect(result.category, equals('finance'));
      expect(result.engineName, equals('litert_model'));
      expect(result.score, greaterThan(0.50));
      expect(result.matchedSignals.first, contains('Softmax scores'));
    });

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
  });
}

