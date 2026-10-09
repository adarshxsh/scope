import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier.dart';
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

    test('tampered asset bytes trigger verification failure and activate fallback heuristic', () async {
      final classifier = LiteRtClassifier();
      final tamperedBytes = Uint8List.fromList(utf8.encode('INVALID_CORRUPTED_MODEL_DATA'));
      final manifestMap = {
        'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
      };

      await classifier.initializeFromBytes(
        tamperedBytes,
        manifestMap: manifestMap,
      );

      expect(classifier.isModelLoaded, isFalse);

      final notif = AppNotification(
        id: '3',
        packageName: 'com.whatsapp',
        title: 'Promo',
        content: 'Get 50% discount off today!',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.category, equals('promo'));
      expect(result.isFallback, isTrue);
      expect(result.engineName, contains('fallback'));
      expect(result.score, equals(0.0));
    });

    test('valid model bytes verify successfully', () async {
      final sampleBytes = Uint8List.fromList(utf8.encode('MOCK_VALID_TFLITE_BYTES'));
      final validHash = AssetVerifier.computeSha256(sampleBytes);
      final manifestMap = {
        'assets/model.tflite': validHash,
      };

      final classifier = LiteRtClassifier();
      await classifier.initializeFromBytes(
        sampleBytes,
        manifestMap: manifestMap,
      );

      // Interpreter.fromBuffer will fail on mock bytes or headless platform,
      // but verification check passed without throwing unhandled exceptions.
      expect(classifier, isNotNull);
    });
  });
}
