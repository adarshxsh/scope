import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier_service.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerifierService Tests', () {
    setUp(() {
      AssetVerifierService.instance.resetPublicKeys();
      AssetVerifierService.instance.setCustomAssetLoader(null);
    });

    tearDown(() {
      AssetVerifierService.instance.resetPublicKeys();
      AssetVerifierService.instance.setCustomAssetLoader(null);
    });

    test('verifies genuine assets/manifest.json signature against embedded public key', () async {
      final isManifestValid = await AssetVerifierService.instance.verifyManifest();
      expect(isManifestValid, isTrue);
    });

    test('verifies genuine SHA-256 digests for model.tflite, rules.json, and vocab.txt', () async {
      final modelVerified = await AssetVerifierService.instance.verifyAsset('assets/model.tflite');
      final rulesVerified = await AssetVerifierService.instance.verifyAsset('assets/rules.json');
      final vocabVerified = await AssetVerifierService.instance.verifyAsset('assets/vocab.txt');

      expect(modelVerified, isTrue);
      expect(rulesVerified, isTrue);
      expect(vocabVerified, isTrue);
    });

    test('asset verification overhead remains under 10 milliseconds', () async {
      await AssetVerifierService.instance.verifyManifest();

      final stopwatch = Stopwatch()..start();
      await AssetVerifierService.instance.verifyAsset('assets/rules.json');
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10));
    });

    test('rejects verification if asset contents are tampered or corrupted', () async {
      final tamperedBytes = Uint8List.fromList(utf8.encode('CORRUPTED MODEL CONTENT'));

      final isVerified = await AssetVerifierService.instance.verifyAsset(
        'assets/model.tflite',
        customBytes: tamperedBytes,
      );

      expect(isVerified, isFalse);
    });

    test('rejects manifest verification if digital signature is tampered or invalid', () async {
      const invalidManifestJson = '''
{
  "version": "1.0.0",
  "files": {
    "assets/model.tflite": "63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6"
  },
  "signature": "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
}
''';

      final isValid = await AssetVerifierService.instance.verifyManifest(
        manifestJsonOverride: invalidManifestJson,
      );

      expect(isValid, isFalse);
    });

    test('supports public key rotation via addAuthorizedPublicKey', () async {
      final ed25519 = Ed25519();
      final keyPair = await ed25519.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();

      final publicKeyHex = publicKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final Map<String, dynamic> manifestMap = {
        'version': '1.0.0',
        'files': {
          'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
        },
      };

      // Canonical payload bytes
      final canonicalStr = jsonEncode({
        'files': {'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6'},
        'version': '1.0.0',
      });
      final payloadBytes = utf8.encode(canonicalStr);

      final signature = await ed25519.sign(payloadBytes, keyPair: keyPair);
      final signatureHex = signature.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      manifestMap['signature'] = signatureHex;
      final customManifestJson = jsonEncode(manifestMap);

      // Before adding key, verification should fail
      final beforeKeyAdded = await AssetVerifierService.instance.verifyManifest(
        manifestJsonOverride: customManifestJson,
      );
      expect(beforeKeyAdded, isFalse);

      // Add rotated public key
      AssetVerifierService.instance.addAuthorizedPublicKey(publicKeyHex);

      // After adding rotated key, verification should pass
      final afterKeyAdded = await AssetVerifierService.instance.verifyManifest(
        manifestJsonOverride: customManifestJson,
      );
      expect(afterKeyAdded, isTrue);
    });

    test('rejects unregistered assets not present in manifest', () async {
      final isVerified = await AssetVerifierService.instance.verifyAsset('assets/unknown_asset.bin');
      expect(isVerified, isFalse);
    });

    test('GhostAI degrades cleanly to heuristics when model asset verification fails', () async {
      // Mock custom loader returning corrupted bytes for model.tflite
      AssetVerifierService.instance.setCustomAssetLoader((path) async {
        if (path == 'assets/manifest.json') {
          // Return valid manifest
          final realManifest = '''
{
  "version": "1.0.0",
  "files": {
    "assets/model.tflite": "63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6"
  },
  "signature": "4c1a2d97c88d4464f8bfe697d7319597ef72e8ab3b6aeddcf6821c2ddde49c2478e37b90a317ab13e10e8f02e3dfee0363625a9b3debd92f16c8797a33236008"
}
''';
          return Uint8List.fromList(utf8.encode(realManifest));
        }
        if (path == 'assets/model.tflite') {
          return Uint8List.fromList(utf8.encode('TAMPERED MODEL BINARY'));
        }
        return null;
      });

      // Verify that AssetVerifierService rejects tampered model
      final modelVerified = await AssetVerifierService.instance.verifyAsset('assets/model.tflite');
      expect(modelVerified, isFalse);

      // Inference should complete without crashing using heuristic fallback
      final notif = AppNotification(
        id: 'test-tampered-1',
        packageName: 'com.whatsapp',
        title: 'Security Alert',
        content: 'Your OTP is 991823.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await GhostAI.predict(notif);
      expect(result.reviewScore, equals(1.0)); // OTP heuristic fallback
    });

    test('LiteRtClassifier degrades cleanly to fallback when vocab verification fails', () async {
      AssetVerifierService.instance.setCustomAssetLoader((path) async {
        if (path == 'assets/vocab.txt') {
          return Uint8List.fromList(utf8.encode('CORRUPTED VOCAB'));
        }
        return null;
      });

      final classifier = LiteRtClassifier();
      final notif = AppNotification(
        id: 'test-litert-fallback',
        packageName: 'com.example.bank',
        title: 'Account Alert',
        content: 'Your account was debited Rs 500.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      expect(result.engineName, contains('fallback'));
      expect(result.category, equals('finance'));
    });
  });
}
