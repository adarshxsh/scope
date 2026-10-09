class AssetIntegrityRegistry {
  static final Map<String, String> _checksums = {
    'assets/model.tflite':
        '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
    'assets/rules.json':
        '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
    'assets/vocab.txt':
        '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
  };

  /// Returns expected SHA-256 digest for an asset path, or null if unregistered.
  static String? getExpectedChecksum(String assetPath) {
    return _checksums[assetPath];
  }

  /// Registers or overrides expected SHA-256 digest for an asset path.
  static void registerAsset(String assetPath, String expectedChecksum) {
    _checksums[assetPath] = expectedChecksum.toLowerCase();
  }

  /// Checks if an asset path is registered in the integrity registry.
  static bool isRegistered(String assetPath) {
    return _checksums.containsKey(assetPath);
  }

  /// Resets the registry to default ground-truth SHA-256 digests.
  static void resetToDefaults() {
    _checksums.clear();
    _checksums.addAll({
      'assets/model.tflite':
          '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6',
      'assets/rules.json':
          '547e8f356667e6437c101c874cc4a1fd085cf7554174ac5b460a801fbe571937',
      'assets/vocab.txt':
          '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5',
    });
  }
}
