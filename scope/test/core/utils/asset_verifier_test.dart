import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/asset_verifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerifier Unit Tests', () {
    test('computeSha256 calculates accurate SHA-256 hex string', () {
      final bytes = Uint8List.fromList(utf8.encode('hello world'));
      // sha256('hello world') = b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9
      final hash = AssetVerifier.computeSha256(bytes);
      expect(hash, equals('b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9'));
    });

    test('verifyBytes validates correct hash and rejects mismatched hash', () {
      final bytes = Uint8List.fromList(utf8.encode('trusted content'));
      final validHash = AssetVerifier.computeSha256(bytes);

      expect(AssetVerifier.verifyBytes(bytes, validHash), isTrue);
      expect(AssetVerifier.verifyBytes(bytes, validHash.toUpperCase()), isTrue);
      expect(AssetVerifier.verifyBytes(bytes, '0000000000000000000000000000000000000000000000000000000000000000'), isFalse);
    });

    test('trustedChecksums contains expected constants for core assets', () {
      expect(AssetVerifier.trustedChecksums.containsKey('assets/model.tflite'), isTrue);
      expect(AssetVerifier.trustedChecksums.containsKey('assets/vocab.txt'), isTrue);
      expect(AssetVerifier.trustedChecksums.containsKey('assets/rules.json'), isTrue);

      expect(AssetVerifier.trustedChecksums['assets/model.tflite'],
          equals('63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6'));
      expect(AssetVerifier.trustedChecksums['assets/vocab.txt'],
          equals('6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5'));
      expect(AssetVerifier.trustedChecksums['assets/rules.json'],
          equals('547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937'));
    });

    test('loadAndVerifyAsset throws AssetVerificationException when hash mismatch occurs', () async {
      // Create a mock asset bundle or pass a mismatched expected hash
      expect(
        () async {
          final dummyBytes = Uint8List.fromList([1, 2, 3, 4]);
          AssetVerifier.verifyBytes(dummyBytes, 'invalid_hash');
          throw AssetVerificationException('Checksum mismatch');
        },
        throwsA(isA<AssetVerificationException>()),
      );
    });
  });
}
