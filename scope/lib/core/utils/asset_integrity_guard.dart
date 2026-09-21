import 'package:crypto/crypto.dart';

/// Cryptographic verification utility for model and asset integrity checks before instantiation.
class AssetIntegrityGuard {
  /// Expected SHA-256 digests for pre-compiled application assets.
  static const Map<String, String> defaultManifest = {
    'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'assets/vocab.txt': '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
    'assets/rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
  };

  /// Computes the SHA-256 digest of [bytes] and verifies it against [expectedHash]
  /// or the entry in [defaultManifest] (or optional [manifest]) matching [assetPath].
  static bool verifyAssetBytes(
    String assetPath,
    List<int> bytes, {
    String? expectedHash,
    Map<String, String>? manifest,
  }) {
    final targetManifest = manifest ?? defaultManifest;
    final targetHash = expectedHash ?? targetManifest[assetPath];
    if (targetHash == null || targetHash.isEmpty) {
      return false;
    }
    final computedHash = computeHash(bytes);
    return computedHash.toLowerCase() == targetHash.toLowerCase();
  }

  /// Computes the hex-encoded SHA-256 string for the provided byte buffer.
  static String computeHash(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }
}
