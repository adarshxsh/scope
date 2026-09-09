import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Exception thrown when cryptographic signature or HMAC verification fails.
class RuleSecurityException implements Exception {
  final String message;
  const RuleSecurityException(this.message);

  @override
  String toString() => 'RuleSecurityException: $message';
}

/// Cryptographic helper utilities for rule bundle signature verification and local HMAC protection.
class RuleCrypto {
  /// Hardcoded Scope publisher Ed25519 public key (32 bytes hex).
  static const String publisherPublicKeyHex =
      '79b5562e8fe654f94078b112e8a98ba7901f853ae695bed7e0e3910bad049664';

  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  static Uint8List hexToBytes(String hex) {
    final cleanHex = hex.trim();
    if (cleanHex.length % 2 != 0) {
      throw const FormatException('Invalid hex string length');
    }
    final result = Uint8List(cleanHex.length ~/ 2);
    for (int i = 0; i < cleanHex.length; i += 2) {
      result[i ~/ 2] = int.parse(cleanHex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Verifies the Ed25519 cryptographic signature of a payload string against the publisher public key.
  static bool verifyEd25519Signature({
    required String payloadStr,
    required String signatureHex,
    String? publicKeyHex,
  }) {
    try {
      final keyHex = publicKeyHex ?? publisherPublicKeyHex;
      final pubKey = ed.PublicKey(hexToBytes(keyHex));
      final sigBytes = hexToBytes(signatureHex);
      final msgBytes = Uint8List.fromList(utf8.encode(payloadStr));
      return ed.verify(pubKey, msgBytes, sigBytes);
    } catch (_) {
      return false;
    }
  }

  /// Derives a device-specific key for HMAC computation based on device storage location.
  static List<int> deriveDeviceKey(String storageDir) {
    final salt = 'scope_local_rlhf_key_salt_v1_$storageDir';
    return sha256.convert(utf8.encode(salt)).bytes;
  }

  /// Computes HMAC-SHA256 signature for [payloadStr] using [keyBytes].
  static String computeHMAC({
    required String payloadStr,
    required List<int> keyBytes,
  }) {
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(utf8.encode(payloadStr));
    return digest.toString();
  }

  /// Verifies HMAC-SHA256 signature for [payloadStr].
  static bool verifyHMAC({
    required String payloadStr,
    required String expectedHmacHex,
    required List<int> keyBytes,
  }) {
    final computed = computeHMAC(payloadStr: payloadStr, keyBytes: keyBytes);
    return computed.toLowerCase() == expectedHmacHex.trim().toLowerCase();
  }
}
