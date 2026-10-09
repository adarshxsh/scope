import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/utils/asset_integrity_guard.dart';

void main() {
  group('AssetIntegrityGuard Tests', () {
    test('computeHash computes correct SHA-256 hex string', () {
      final bytes = utf8.encode('hello world');
      final hash = AssetIntegrityGuard.computeHash(bytes);
      expect(hash, equals('b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9'));
    });

    test('verifyAssetBytes succeeds when hash matches custom expected hash', () {
      final bytes = utf8.encode('valid asset payload');
      final expectedHash = AssetIntegrityGuard.computeHash(bytes);

      final isValid = AssetIntegrityGuard.verifyAssetBytes(
        'custom/asset.txt',
        bytes,
        expectedHash: expectedHash,
      );

      expect(isValid, isTrue);
    });

    test('verifyAssetBytes fails when hash does not match expected hash', () {
      final bytes = utf8.encode('corrupted payload');
      final expectedHash = '0000000000000000000000000000000000000000000000000000000000000000';

      final isValid = AssetIntegrityGuard.verifyAssetBytes(
        'custom/asset.txt',
        bytes,
        expectedHash: expectedHash,
      );

      expect(isValid, isFalse);
    });

    test('verifyAssetBytes validates against defaultManifest entries', () {
      final vocabHash = AssetIntegrityGuard.defaultManifest['assets/vocab.txt'];
      expect(vocabHash, equals('6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5'));

      final modelHash = AssetIntegrityGuard.defaultManifest['assets/model.tflite'];
      expect(modelHash, equals('63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6'));

      final rulesHash = AssetIntegrityGuard.defaultManifest['assets/rules.json'];
      expect(rulesHash, equals('547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937'));
    });

    test('verifyAssetBytes performs case-insensitive hash comparison', () {
      final bytes = utf8.encode('test asset data');
      final expectedHash = AssetIntegrityGuard.computeHash(bytes).toUpperCase();

      final isValid = AssetIntegrityGuard.verifyAssetBytes(
        'custom/asset.txt',
        bytes,
        expectedHash: expectedHash,
      );

      expect(isValid, isTrue);
    });
  });
}
