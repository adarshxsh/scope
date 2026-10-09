import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier.dart';

class TestAssetBundle extends AssetBundle {
  final Map<String, String> stringAssets;
  final Map<String, Uint8List> byteAssets;

  TestAssetBundle({
    this.stringAssets = const {},
    this.byteAssets = const {},
  });

  @override
  Future<ByteData> load(String key) async {
    if (byteAssets.containsKey(key)) {
      final bytes = byteAssets[key]!;
      return ByteData.sublistView(bytes);
    }
    if (stringAssets.containsKey(key)) {
      final bytes = Uint8List.fromList(stringAssets[key]!.codeUnits);
      return ByteData.sublistView(bytes);
    }
    throw FlutterError('Asset not found: $key');
  }

  @override
  Future<T> loadStructuredData<T>(
      String key, Future<T> Function(String value) parser) async {
    final str = stringAssets[key] ?? '';
    return parser(str);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerifier Unit Tests', () {
    const testPath = 'assets/vocab.txt';
    const validDigest =
        '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

    test('computeHash produces valid SHA-256 hex string', () {
      final bytes = Uint8List.fromList('hello world'.codeUnits);
      final hash = AssetVerifier.computeHash(bytes);
      expect(
        hash,
        equals('b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9'),
      );
    });

    test('verifyBytes passes with valid expected hash', () {
      final bytes = Uint8List.fromList('test payload'.codeUnits);
      final hash = AssetVerifier.computeHash(bytes);

      final result = AssetVerifier.verifyBytes(
        bytes,
        'assets/custom.txt',
        expectedHash: hash,
      );

      expect(result, isTrue);
    });

    test('verifyBytes throws AssetVerificationException on digest mismatch', () {
      final bytes = Uint8List.fromList('tampered payload'.codeUnits);

      expect(
        () => AssetVerifier.verifyBytes(
          bytes,
          testPath,
          expectedHash: validDigest,
        ),
        throwsA(isA<AssetVerificationException>()),
      );
    });

    test('verifyBytes throws when no expected digest exists for unknown asset', () {
      final bytes = Uint8List.fromList('unknown payload'.codeUnits);

      expect(
        () => AssetVerifier.verifyBytes(bytes, 'assets/unknown_asset.dat'),
        throwsA(isA<AssetVerificationException>()),
      );
    });

    test('verifyAsset succeeds with matching asset bundle content', () async {
      final mockContent = Uint8List.fromList('valid payload'.codeUnits);
      final hash = AssetVerifier.computeHash(mockContent);

      final bundle = TestAssetBundle(
        byteAssets: {'assets/test_model.tflite': mockContent},
      );

      final verified = await AssetVerifier.verifyAsset(
        'assets/test_model.tflite',
        bundle: bundle,
        expectedHash: hash,
      );

      expect(verified, isTrue);
    });

    test('verifyAsset throws AssetVerificationException on tampered bundle content', () async {
      final mockContent = Uint8List.fromList('tampered content'.codeUnits);

      final bundle = TestAssetBundle(
        byteAssets: {'assets/vocab.txt': mockContent},
      );

      expect(
        () => AssetVerifier.verifyAsset('assets/vocab.txt', bundle: bundle),
        throwsA(isA<AssetVerificationException>()),
      );
    });
  });
}
