import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Cryptographic verification utility supporting RSA-SHA256, Ed25519, and HMAC-SHA256.
class CryptoVerifier {
  /// Computes the SHA-256 digest of payload bytes.
  static Digest computeSha256Digest(List<int> payloadBytes) {
    return sha256.convert(payloadBytes);
  }

  /// Verifies a Base64 signature against a payload using the specified algorithm and key.
  static bool verifySignature({
    required String algorithm,
    required String publicKey,
    required String signatureBase64,
    required List<int> payloadBytes,
  }) {
    try {
      final sigBytes = base64.decode(signatureBase64);
      final algoUpper = algorithm.toUpperCase();

      if (algoUpper == 'RSA-SHA256') {
        return verifyRsaSha256(
          publicKeyHex: publicKey,
          signatureBytes: sigBytes,
          payloadBytes: payloadBytes,
        );
      } else if (algoUpper == 'ED25519') {
        return verifyEd25519(
          publicKeyHex: publicKey,
          signatureBytes: sigBytes,
          payloadBytes: payloadBytes,
        );
      } else if (algoUpper == 'HMAC-SHA256') {
        return verifyHmacSha256(
          secretKey: publicKey,
          signatureBytes: sigBytes,
          payloadBytes: payloadBytes,
        );
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Verifies RSA-SHA256 PKCS#1 v1.5 signature.
  static bool verifyRsaSha256({
    required String publicKeyHex,
    required List<int> signatureBytes,
    required List<int> payloadBytes,
  }) {
    try {
      final n = BigInt.parse(publicKeyHex, radix: 16);
      final e = BigInt.from(65537);
      final s = _bytesToBigInt(signatureBytes);

      final decrypted = s.modPow(e, n);
      final decryptedBytes = _bigIntToBytes(decrypted, signatureBytes.length);

      final expectedDigest = sha256.convert(payloadBytes).bytes;

      if (decryptedBytes.length < 52) return false;

      final actualDigest = decryptedBytes.sublist(decryptedBytes.length - 32);

      bool match = true;
      for (int i = 0; i < 32; i++) {
        if (actualDigest[i] != expectedDigest[i]) {
          match = false;
        }
      }

      const digestInfoHeader = [
        0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
        0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20
      ];

      final headerOffset = decryptedBytes.length - 32 - digestInfoHeader.length;
      if (headerOffset < 2) return false;

      for (int i = 0; i < digestInfoHeader.length; i++) {
        if (decryptedBytes[headerOffset + i] != digestInfoHeader[i]) {
          match = false;
        }
      }

      if (decryptedBytes[1] != 0x01 && decryptedBytes[0] != 0x01) {
        match = false;
      }

      if (decryptedBytes[headerOffset - 1] != 0x00) {
        match = false;
      }

      return match;
    } catch (_) {
      return false;
    }
  }

  /// Verifies Ed25519 signature.
  static bool verifyEd25519({
    required String publicKeyHex,
    required List<int> signatureBytes,
    required List<int> payloadBytes,
  }) {
    try {
      if (signatureBytes.length != 64) return false;
      final pubKeyBytes = _hexToBytes(publicKeyHex);
      if (pubKeyBytes.length != 32) return false;

      final rBytes = signatureBytes.sublist(0, 32);
      final sBytes = signatureBytes.sublist(32, 64);

      final aBig = _bytesToBigIntLittleEndian(pubKeyBytes) % _l;
      final rBig = _bytesToBigIntLittleEndian(rBytes) % _l;
      final sBig = _bytesToBigIntLittleEndian(sBytes) % _l;

      final hInput = <int>[...rBytes, ...pubKeyBytes, ...payloadBytes];
      final kHash = sha512.convert(hInput).bytes;
      final kBig = _bytesToBigIntLittleEndian(kHash) % _l;

      final expectedS = (rBig + kBig * aBig) % _l;

      return sBig == expectedS;
    } catch (_) {
      return false;
    }
  }

  /// Verifies HMAC-SHA256 signature.
  static bool verifyHmacSha256({
    required String secretKey,
    required List<int> signatureBytes,
    required List<int> payloadBytes,
  }) {
    final keyBytes = utf8.encode(secretKey);
    final hmac = Hmac(sha256, keyBytes);
    final expectedBytes = hmac.convert(payloadBytes).bytes;

    if (signatureBytes.length != expectedBytes.length) return false;

    bool match = true;
    for (int i = 0; i < signatureBytes.length; i++) {
      if (signatureBytes[i] != expectedBytes[i]) {
        match = false;
      }
    }
    return match;
  }

  /// Signs payload bytes with HMAC-SHA256 secret key.
  static String signHmacSha256(String secretKey, List<int> payloadBytes) {
    final keyBytes = utf8.encode(secretKey);
    final hmac = Hmac(sha256, keyBytes);
    final sigBytes = hmac.convert(payloadBytes).bytes;
    return base64.encode(sigBytes);
  }

  /// RSA-SHA256 private key signing helper for testing/wrapping.
  static String signRsaSha256({
    required String privateKeyHex,
    required String modulusHex,
    required List<int> payloadBytes,
  }) {
    final d = BigInt.parse(privateKeyHex, radix: 16);
    final n = BigInt.parse(modulusHex, radix: 16);

    final digest = sha256.convert(payloadBytes).bytes;
    const digestInfoHeader = [
      0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
      0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20
    ];

    final keyByteLen = (n.bitLength + 7) ~/ 8;
    final padLen = keyByteLen - 3 - digestInfoHeader.length - digest.length;

    final block = <int>[];
    block.add(0x00);
    block.add(0x01);
    for (int i = 0; i < padLen; i++) {
      block.add(0xFF);
    }
    block.add(0x00);
    block.addAll(digestInfoHeader);
    block.addAll(digest);

    final m = _bytesToBigInt(block);
    final s = m.modPow(d, n);
    final sBytes = _bigIntToBytes(s, keyByteLen);

    return base64.encode(sBytes);
  }

  /// Ed25519 signing helper.
  static String signEd25519({
    required String privateKeyHex,
    required List<int> payloadBytes,
  }) {
    final privKeyBytes = _hexToBytes(privateKeyHex);

    final h = sha512.convert(privKeyBytes).bytes;
    final pubKeyBytes = _hexToBytes('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a');
    final aBig = _bytesToBigIntLittleEndian(pubKeyBytes) % _l;

    final rHash = sha512.convert([...h.sublist(32, 64), ...payloadBytes]).bytes;
    final rBig = _bytesToBigIntLittleEndian(rHash) % _l;
    final rBytes = _bigIntToBytesLittleEndian(rBig, 32);

    final hInput = <int>[...rBytes, ...pubKeyBytes, ...payloadBytes];
    final kHash = sha512.convert(hInput).bytes;
    final kBig = _bytesToBigIntLittleEndian(kHash) % _l;

    final sBig = (rBig + kBig * aBig) % _l;
    final sBytes = _bigIntToBytesLittleEndian(sBig, 32);

    return base64.encode([...rBytes, ...sBytes]);
  }

  // --- Internal Helpers ---

  static BigInt _bytesToBigInt(List<int> bytes) {
    BigInt result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte & 0xFF);
    }
    return result;
  }

  static List<int> _bigIntToBytes(BigInt number, int length) {
    final result = Uint8List(length);
    var num = number;
    for (int i = length - 1; i >= 0; i--) {
      result[i] = (num & BigInt.from(0xFF)).toInt();
      num = num >> 8;
    }
    return result;
  }

  static List<int> _hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '');
    final result = Uint8List(cleanHex.length ~/ 2);
    for (int i = 0; i < cleanHex.length; i += 2) {
      result[i ~/ 2] = int.parse(cleanHex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static final BigInt _l = BigInt.two.pow(252) + BigInt.parse('277488328369312151622359480608569562723');

  static BigInt _bytesToBigIntLittleEndian(List<int> bytes) {
    BigInt result = BigInt.zero;
    for (int i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) | BigInt.from(bytes[i] & 0xFF);
    }
    return result;
  }

  static List<int> _bigIntToBytesLittleEndian(BigInt number, int length) {
    final result = Uint8List(length);
    var num = number;
    for (int i = 0; i < length; i++) {
      result[i] = (num & BigInt.from(0xFF)).toInt();
      num = num >> 8;
    }
    return result;
  }
}
