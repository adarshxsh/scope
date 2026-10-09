import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

class TamperedAssetBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final tamperedBytes = Uint8List.fromList('tampered byte content'.codeUnits);
    return ByteData.sublistView(tamperedBytes);
  }

  @override
  Future<T> loadStructuredData<T>(
      String key, Future<T> Function(String value) parser) async {
    return parser('tampered text');
  }
}

class MockTensor implements Tensor {
  final List<int> _shape;
  MockTensor(this._shape);

  @override
  List<int> get shape => _shape;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInterpreter implements Interpreter {
  @override
  Tensor getInputTensor(int index) => MockTensor([1, 64]);

  @override
  Tensor getOutputTensor(int index) => MockTensor([1, 5]);

  @override
  void run(Object input, Object output) {
    if (output is List && output.isNotEmpty && output[0] is List) {
      final outList = output[0] as List;
      if (outList.length >= 5) {
        outList[0] = 0.1; // promo
        outList[1] = 0.2; // social
        outList[2] = 0.1; // sys
        outList[3] = 0.1; // msg
        outList[4] = 4.5; // finance (highest logit)
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

    test('tampered asset hash triggers safe fallback mode with isModelLoaded = false', () async {
      final classifier = LiteRtClassifier(assetBundle: TamperedAssetBundle());

      final notif = AppNotification(
        id: '3',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isModelLoaded, isFalse);
      expect(result.isFallback, isTrue);
      expect(result.score, equals(0.0));
      expect(result.engineName, contains('fallback'));
    });

    test('valid model interpreter execution returns authentic softmax confidence scores', () async {
      final fakeInterpreter = FakeInterpreter();
      final classifier = LiteRtClassifier(interpreter: fakeInterpreter);

      final notif = AppNotification(
        id: '4',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isModelLoaded, isTrue);
      expect(result.isFallback, isFalse);
      expect(result.engineName, equals('litert_model'));
      expect(result.category, equals('finance'));
      expect(result.score, greaterThan(0.9));
    });
  });
}
