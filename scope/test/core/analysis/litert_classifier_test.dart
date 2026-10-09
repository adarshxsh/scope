import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRtClassifier Integrity & Fallback Tests', () {
    test('has correct default SHA-256 asset checksums defined', () {
      expect(
        LiteRtClassifier.defaultModelHash,
        equals(
          '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
        ),
      );
      expect(
        LiteRtClassifier.defaultVocabHash,
        equals(
          '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
        ),
      );
    });

    test('rejects initialization when model SHA-256 checksum mismatches', () async {
      final classifier = LiteRtClassifier(
        expectedModelHash:
            '0000000000000000000000000000000000000000000000000000000000000000',
      );

      final notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your account code is 123456.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isModelLoaded, isFalse);
      expect(result.isFallback, isTrue);
      expect(result.score, equals(0.0));
      expect(result.engineName, equals('litert_model (fallback)'));
      expect(
        result.matchedSignals.any((s) => s.contains('checksum mismatch')),
        isTrue,
      );
    });

    test('rejects initialization when vocab SHA-256 checksum mismatches', () async {
      final classifier = LiteRtClassifier(
        expectedVocabHash:
            '0000000000000000000000000000000000000000000000000000000000000000',
      );

      final notif = AppNotification(
        id: '2',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Hello, how are you?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isModelLoaded, isFalse);
      expect(result.isFallback, isTrue);
      expect(result.score, equals(0.0));
      expect(result.engineName, equals('litert_model (fallback)'));
      expect(
        result.matchedSignals.any((s) => s.contains('checksum mismatch')),
        isTrue,
      );
    });

    test('initializes and falls back gracefully to heuristic classifier when dynamic library is missing', () async {
      final classifier = LiteRtClassifier();

      final notif = AppNotification(
        id: '3',
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
        id: '4',
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
  });
}
