import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Ground truth SHA-256 digests for application model, vocabulary, and rule assets.
const Map<String, String> expectedHashes = {
  'assets/model.tflite': '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
  'assets/vocab.txt': '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
  'assets/rules.json': '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
};

/// Helper utility for computing and verifying SHA-256 asset checksums.
class AssetIntegrity {
  static Map<String, String>? _overrideHashes;

  /// Returns active expected hashes (allowing temporary test overrides).
  static Map<String, String> get activeHashes => _overrideHashes ?? expectedHashes;

  /// Calculates SHA-256 hex string for a byte list.
  static String computeSha256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Verifies byte list against expected SHA-256 digest for assetPath.
  static bool verify(String assetPath, List<int> bytes, {Map<String, String>? customHashes}) {
    final hashes = customHashes ?? activeHashes;
    final expected = hashes[assetPath];
    if (expected == null) {
      debugPrint('AssetIntegrity: No expected hash found for $assetPath');
      return false;
    }

    final actual = computeSha256(bytes);
    final isValid = actual.toLowerCase() == expected.toLowerCase();
    if (!isValid) {
      debugPrint('AssetIntegrity: SHA-256 mismatch for $assetPath! Expected: $expected, Actual: $actual');
    }
    return isValid;
  }

  /// Sets temporary hash overrides for testing corrupted assets.
  @visibleForTesting
  static void setTestHashes(Map<String, String>? hashes) {
    _overrideHashes = hashes != null ? Map.from(hashes) : null;
  }
}
