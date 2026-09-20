import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verification_engine.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerificationEngine Tests', () {
    final verifier = AssetVerificationEngine.instance;

    setUp(() {
      verifier.resetManifest();
    });

    tearDown(() {
      verifier.resetManifest();
    });

    test('verifies default asset manifest entries correctly', () {
      expect(
        verifier.manifest['assets/model.tflite'],
        equals('63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6'),
      );
      expect(
        verifier.manifest['assets/vocab.txt'],
        equals('6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5'),
      );
      expect(
        verifier.manifest['assets/rules.json'],
        equals('547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937'),
      );
    });

    test('detects tampered assets when SHA-256 hash does not match expected manifest', () async {
      // Inject a tampered/mismatched expected hash for vocab.txt
      verifier.setExpectedHash('assets/vocab.txt', '0000000000000000000000000000000000000000000000000000000000000000');

      final result = await verifier.loadAndVerifyString('assets/vocab.txt');

      expect(result, isNull);
      expect(verifier.verificationStatuses['assets/vocab.txt'], equals(AssetVerificationStatus.failed));
      expect(verifier.isAssetVerified('assets/vocab.txt'), isFalse);
    });

    test('failed verification routes LiteRtClassifier to fallback heuristic with zero score', () async {
      // Corrupt model manifest entry to simulate failed integrity check
      verifier.setExpectedHash('assets/model.tflite', '1111111111111111111111111111111111111111111111111111111111111111');

      final classifier = LiteRtClassifier();

      final notif = AppNotification(
        id: 'test_tampered_1',
        packageName: 'com.whatsapp',
        title: 'Security Code',
        content: 'Your verification OTP is 123456.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(classifier.isModelLoaded, isFalse);
      expect(result.isFallback, isTrue);
      expect(result.score, equals(0.0));
      expect(result.engineName, contains('fallback'));
    });

    test('failed verification routes GhostAI gracefully to fallback heuristic without crashing', () async {
      verifier.setExpectedHash('assets/rules.json', '2222222222222222222222222222222222222222222222222222222222222222');

      final notif = AppNotification(
        id: 'test_tampered_2',
        packageName: 'com.example.app',
        title: 'Important Alert',
        content: 'Your balance is low.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);

      expect(result, isNotNull);
      expect(result.reviewScore, isA<double>());
    });

    test('resetManifest restores default expected signed hashes', () {
      verifier.setExpectedHash('assets/vocab.txt', 'invalid_hash');
      expect(verifier.manifest['assets/vocab.txt'], equals('invalid_hash'));

      verifier.resetManifest();

      expect(
        verifier.manifest['assets/vocab.txt'],
        equals('6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5'),
      );
    });
  });
}
