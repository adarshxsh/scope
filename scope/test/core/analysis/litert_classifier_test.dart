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

    test('queries inputVectorDimension from metadata headers dynamically', () {
      final classifier128 = LiteRtClassifier(
        metadata: {
          'feature_vector_size': 128,
          'flutter': {'input_shape': [1, 128]}
        },
      );
      expect(classifier128.inputVectorDimension, equals(128));

      final classifier256 = LiteRtClassifier(
        metadata: {
          'feature_vector_size': 256,
          'flutter': {'input_shape': [1, 256]}
        },
      );
      expect(classifier256.inputVectorDimension, equals(256));
    });

    test('defaults to 128 for backwards compatibility when no metadata present', () {
      final classifier = LiteRtClassifier();
      expect(classifier.inputVectorDimension, equals(128));
    });
  });
}
