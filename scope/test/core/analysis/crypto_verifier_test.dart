import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/crypto_verifier.dart';
import 'package:scope/core/analysis/embedded_keys.dart';

void main() {
  group('EmbeddedKeys & PublicKeyMetadata', () {
    test('retrieves root key correctly', () {
      final key = EmbeddedKeys.getKey('scope-root-key-1');
      expect(key, isNotNull);
      expect(key!.algorithm, equals('RSA-SHA256'));
      expect(key.active, isTrue);
      expect(key.isValid(), isTrue);
    });

    test('rejects inactive or revoked key', () {
      final key = EmbeddedKeys.getKey('scope-revoked-key-0');
      expect(key, isNull);
    });

    test('registers dynamic key for key rotation', () {
      EmbeddedKeys.registerKey(const PublicKeyMetadata(
        keyId: 'test-rotation-key',
        algorithm: 'HMAC-SHA256',
        publicKey: 'test-secret-123',
        active: true,
      ));

      final key = EmbeddedKeys.getKey('test-rotation-key');
      expect(key, isNotNull);
      expect(key!.publicKey, equals('test-secret-123'));
    });
  });

  group('CryptoVerifier', () {
    const testSecret = 'my-secret-key';
    final payloadBytes = utf8.encode('{"version":"1.0.0","rules":[]}');

    test('computes SHA-256 payload digest', () {
      final digest = CryptoVerifier.computeSha256Digest(payloadBytes);
      expect(digest.toString(), isNotEmpty);
      expect(digest.bytes.length, equals(32));
    });

    test('signs and verifies HMAC-SHA256 signature', () {
      final sigBase64 = CryptoVerifier.signHmacSha256(testSecret, payloadBytes);
      expect(sigBase64, isNotEmpty);

      final isValid = CryptoVerifier.verifySignature(
        algorithm: 'HMAC-SHA256',
        publicKey: testSecret,
        signatureBase64: sigBase64,
        payloadBytes: payloadBytes,
      );
      expect(isValid, isTrue);
    });

    test('rejects HMAC-SHA256 signature on tampered payload', () {
      final sigBase64 = CryptoVerifier.signHmacSha256(testSecret, payloadBytes);
      final tamperedPayloadBytes = utf8.encode('{"version":"1.0.0","rules":[{"id":"malicious"}]}');

      final isValid = CryptoVerifier.verifySignature(
        algorithm: 'HMAC-SHA256',
        publicKey: testSecret,
        signatureBase64: sigBase64,
        payloadBytes: tamperedPayloadBytes,
      );
      expect(isValid, isFalse);
    });

    test('signs and verifies RSA-SHA256 signature', () {
      const modulusHex =
          'a3e4b48adb7dcf64c02ef92cd17b09d3ba09b38c4f0f8718cbbbbb93bd420376'
          '702b89cdd55adc77d6324736d546d88778ff86563e8d1c6d09ce6938a9b45b29'
          '7039b5caedc1ce5772dff6bb6a10b9da103a04587a47a58d2a67b3cd4a1c1eb9'
          '4e4548072f8f62a961e78191522b368da42e8a0d63743768dc7ba737f8d0069a'
          '8a2812b4439470f3fad40355d2e282629a65bef87d3590052688635db41dc6f9'
          'f88b19bb69f4970482ef12e5e6d6121f5eeead0e21da111d49335b6991493a3e'
          'f4e4978b8abd5dce81f2c13c353dbc48a36b47c82f682c72990409993c8b47b8'
          'c1961995d03ac23012d1e97ddab5e09ac04d75d40fbe07efde0107e01c4e59f5';

      const privKeyHex =
          '0ae395dc38ef8fb133b49b410f4cf3aef1c815ba0f81aa59eb2556b5dee7ed27'
          '7815e872b8c76fe8f55e034dc11753291310b519f34f7851454ac5c26a420da1'
          '7fef91a4c12db47a2a6b776ee5c1e53b380346c9231cb202e24ba00e566b6e5e'
          '24f564eef749b946243757ac324fa530fd74cb1ecf1a08596af6bb3a34898bba'
          'ab144bd64dad1f049b84779bbf46067099d5602447e2f2fd55887a9fb5c3fc68'
          'aaf88d71bfdd5a46633e56fed3e66b2d1deb011200952267d85aa4d89db87cdc'
          '74c5ec451c62ecd8c718fc455fc99832714d20f18cc848d8a22ab38ca3b4cd7b'
          '08ddc1ba5c91b059e9cd8fee9f3e511deff863c5cb1b297a141b412d51fbab39';

      final sigBase64 = CryptoVerifier.signRsaSha256(
        privateKeyHex: privKeyHex,
        modulusHex: modulusHex,
        payloadBytes: payloadBytes,
      );

      final isValid = CryptoVerifier.verifyRsaSha256(
        publicKeyHex: modulusHex,
        signatureBytes: base64.decode(sigBase64),
        payloadBytes: payloadBytes,
      );
      expect(isValid, isTrue);

      final isTamperedValid = CryptoVerifier.verifyRsaSha256(
        publicKeyHex: modulusHex,
        signatureBytes: base64.decode(sigBase64),
        payloadBytes: utf8.encode('tampered'),
      );
      expect(isTamperedValid, isFalse);
    });

    test('signs and verifies Ed25519 signature', () {
      const privHex = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
      const pubHex = 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';

      final sigBase64 = CryptoVerifier.signEd25519(
        privateKeyHex: privHex,
        payloadBytes: payloadBytes,
      );

      final isValid = CryptoVerifier.verifySignature(
        algorithm: 'Ed25519',
        publicKey: pubHex,
        signatureBase64: sigBase64,
        payloadBytes: payloadBytes,
      );
      expect(isValid, isTrue);

      final isTamperedValid = CryptoVerifier.verifySignature(
        algorithm: 'Ed25519',
        publicKey: pubHex,
        signatureBase64: sigBase64,
        payloadBytes: utf8.encode('tampered'),
      );
      expect(isTamperedValid, isFalse);
    });
  });
}
