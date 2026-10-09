import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Cryptographic helper for key derivation and HMAC signing for local custom rule sets.
class RuleCrypto {
  static const String _defaultDeviceSalt = 'scope_rule_crypto_v1_device_salt_2026';

  /// Derives a deterministic device-bound secret key for HMAC authentication.
  static List<int> deriveDeviceKey([String seed = 'scope_device_unique_seed']) {
    final hmac = Hmac(sha256, utf8.encode(_defaultDeviceSalt));
    final digest = hmac.convert(utf8.encode(seed));
    return digest.bytes;
  }

  /// Computes HMAC-SHA256 signature hex string for data string.
  static String computeHmacHex(String data, List<int> key) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(data));
    return digest.toString().toLowerCase();
  }

  /// Computes HMAC-SHA256 signature bytes for raw payload bytes.
  static Uint8List computeHmacBytes(Uint8List payload, List<int> key) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(payload);
    return Uint8List.fromList(digest.bytes);
  }

  /// Verifies an HMAC-SHA256 signature hex string against data.
  static bool verifyHmac(String data, String signatureHex, List<int> key) {
    final computedHex = computeHmacHex(data, key);
    return computedHex == signatureHex.trim().toLowerCase();
  }
}
