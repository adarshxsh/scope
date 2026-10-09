import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerifier Unit Tests', () {
    test('computeSha256 computes correct SHA-256 digest for byte sequence', () {
      final bytes = Uint8List.fromList(utf8.encode('hello world'));
      final digest = AssetVerifier.computeSha256(bytes);
      expect(digest, equals('b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9'));
    });

    test('verifyBytes validates matching hash and rejects tampered bytes', () {
      final original = Uint8List.fromList(utf8.encode('valid asset content'));
      final expectedHash = AssetVerifier.computeSha256(original);

      expect(AssetVerifier.verifyBytes(original, expectedHash), isTrue);

      final tampered = Uint8List.fromList(utf8.encode('tampered asset content'));
      expect(AssetVerifier.verifyBytes(tampered, expectedHash), isFalse);
    });

    test('loadAndVerify loads and verifies model.tflite successfully', () async {
      final bytes = await AssetVerifier.loadAndVerify('assets/model.tflite');
      expect(bytes, isNotEmpty);
      final computed = AssetVerifier.computeSha256(bytes);
      expect(computed, equals(AssetVerifier.modelSha256));
    });

    test('loadAndVerify loads and verifies rules.json successfully', () async {
      final bytes = await AssetVerifier.loadAndVerify('assets/rules.json');
      expect(bytes, isNotEmpty);
      final computed = AssetVerifier.computeSha256(bytes);
      expect(computed, equals(AssetVerifier.rulesSha256));
    });

    test('loadAndVerify loads and verifies vocab.txt successfully', () async {
      final bytes = await AssetVerifier.loadAndVerify('assets/vocab.txt');
      expect(bytes, isNotEmpty);
      final computed = AssetVerifier.computeSha256(bytes);
      expect(computed, equals(AssetVerifier.vocabSha256));
    });

    test('loadAndVerify throws SecurityException for unregistered asset path', () async {
      expect(
        () => AssetVerifier.loadAndVerify('assets/unknown.json'),
        throwsA(isA<SecurityException>()),
      );
    });
  });
}
