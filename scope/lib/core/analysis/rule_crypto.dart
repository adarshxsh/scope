import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

/// Cryptographic primitives and envelope utilities for Ed25519 base rule verification
/// and device-bound HMAC-SHA256 dynamic custom rule protection.
class RuleCrypto {
  // 32-byte deterministic seed for base rule author keypair
  static final List<int> _authorSeedBytes = utf8.encode('SCOPE_ED25519_SECRET_SEED_KEY_20');

  static SimpleKeyPair? _authorKeyPair;
  static PublicKey? _authorPublicKey;
  static List<int>? _cachedDeviceKey;

  /// Helper to convert dynamic maps/lists to deterministic canonical JSON representation.
  static String canonicalJsonEncode(dynamic object) {
    return json.encode(_canonicalValue(object));
  }

  static dynamic _canonicalValue(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final sortedMap = <String, dynamic>{};
      for (final key in sortedKeys) {
        sortedMap[key] = _canonicalValue(value[key]);
      }
      return sortedMap;
    } else if (value is List) {
      return value.map(_canonicalValue).toList();
    }
    return value;
  }

  /// Gets the Ed25519 author key pair.
  static Future<SimpleKeyPair> _getAuthorKeyPair() async {
    if (_authorKeyPair != null) return _authorKeyPair!;
    final algorithm = Ed25519();
    _authorKeyPair = await algorithm.newKeyPairFromSeed(_authorSeedBytes);
    return _authorKeyPair!;
  }

  /// Gets the Ed25519 author public key.
  static Future<PublicKey> getAuthorPublicKey() async {
    if (_authorPublicKey != null) return _authorPublicKey!;
    final keyPair = await _getAuthorKeyPair();
    _authorPublicKey = await keyPair.extractPublicKey();
    return _authorPublicKey!;
  }

  /// Signs a base rules payload map with the author Ed25519 private key
  /// and returns a signed envelope Map containing `signature` and `payload`.
  static Future<Map<String, dynamic>> createSignedBaseRulesEnvelope(Map<String, dynamic> payloadMap) async {
    final keyPair = await _getAuthorKeyPair();
    final canonicalJson = canonicalJsonEncode(payloadMap);
    final payloadBytes = utf8.encode(canonicalJson);

    final algorithm = Ed25519();
    final signature = await algorithm.sign(payloadBytes, keyPair: keyPair);
    final signatureHex = signature.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return {
      'signature': signatureHex,
      'payload': payloadMap,
    };
  }

  /// Verifies an Ed25519 base rules signature envelope.
  /// Returns the parsed payload map if valid, or `null` if verification fails or signature is missing.
  static Future<Map<String, dynamic>?> verifyBaseRulesEnvelope(Map<String, dynamic> envelopeMap) async {
    try {
      final signatureHex = envelopeMap['signature'] as String?;
      final payload = envelopeMap['payload'];

      if (signatureHex == null || signatureHex.isEmpty || payload == null || payload is! Map) {
        return null;
      }

      final signatureBytes = _hexToBytes(signatureHex);
      if (signatureBytes.length != 64) {
        return null;
      }

      final canonicalJson = canonicalJsonEncode(payload);
      final payloadBytes = utf8.encode(canonicalJson);

      final publicKey = await getAuthorPublicKey();
      final algorithm = Ed25519();

      final signatureObj = Signature(
        signatureBytes,
        publicKey: publicKey,
      );

      final isValid = await algorithm.verify(
        payloadBytes,
        signature: signatureObj,
      );

      if (isValid) {
        return Map<String, dynamic>.from(payload);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  /// Safely resolves the storage directory, falling back to system temp in test environments.
  static Future<Directory> getStorageDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      final tempDir = Directory('${Directory.systemTemp.path}/scope_app_docs');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      return tempDir;
    }
  }

  /// Retrieves or generates a secure 256-bit (32-byte) device-bound key.
  static Future<List<int>> getOrCreateDeviceKey() async {
    if (_cachedDeviceKey != null) return _cachedDeviceKey!;

    try {
      final dir = await getStorageDirectory();
      final keyFile = File('${dir.path}/.device_key');
      if (await keyFile.exists()) {
        final bytes = await keyFile.readAsBytes();
        if (bytes.length == 32) {
          _cachedDeviceKey = bytes;
          return _cachedDeviceKey!;
        }
      }

      // Generate new 32 random bytes
      final rng = Random.secure();
      final newKey = List<int>.generate(32, (_) => rng.nextInt(256));
      await keyFile.writeAsBytes(newKey);
      _cachedDeviceKey = newKey;
      return _cachedDeviceKey!;
    } catch (_) {
      // Fallback in-memory key for unit test / sandbox environments
      if (_cachedDeviceKey == null) {
        final rng = Random.secure();
        _cachedDeviceKey = List<int>.generate(32, (_) => rng.nextInt(256));
      }
      return _cachedDeviceKey!;
    }
  }

  /// Signs a custom dynamic rules payload list/map with the device key using HMAC-SHA256.
  static Future<Map<String, dynamic>> createSignedCustomRulesEnvelope(List<dynamic> rulesList) async {
    final deviceKey = await getOrCreateDeviceKey();
    final payloadMap = {'rules': rulesList};
    final canonicalJson = canonicalJsonEncode(payloadMap);
    final payloadBytes = utf8.encode(canonicalJson);

    final hmac = crypto.Hmac(crypto.sha256, deviceKey);
    final digestHex = hmac.convert(payloadBytes).toString();

    return {
      'hmac': digestHex,
      'payload': payloadMap,
    };
  }

  /// Verifies the HMAC-SHA256 signature header on dynamic custom rules.
  /// Returns the rules list if valid, or `null` if verification fails or file is tampered.
  static Future<List<dynamic>?> verifyCustomRulesEnvelope(Map<String, dynamic> envelopeMap) async {
    try {
      final hmacHex = envelopeMap['hmac'] as String?;
      final payload = envelopeMap['payload'];

      if (hmacHex == null || hmacHex.isEmpty || payload == null || payload is! Map) {
        return null;
      }

      final rulesList = payload['rules'];
      if (rulesList is! List) {
        return null;
      }

      final deviceKey = await getOrCreateDeviceKey();
      final canonicalJson = canonicalJsonEncode(payload);
      final payloadBytes = utf8.encode(canonicalJson);

      final hmac = crypto.Hmac(crypto.sha256, deviceKey);
      final computedDigestHex = hmac.convert(payloadBytes).toString();

      if (computedDigestHex == hmacHex) {
        return rulesList;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  /// Helper to clear cached keys (useful in unit tests).
  static void resetKeysForTesting() {
    _cachedDeviceKey = null;
  }

  static List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
