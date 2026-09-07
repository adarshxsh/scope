import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

void main() {
  test('Ed25519 sign and verify', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    expect(publicKey.bytes, isNotEmpty);

    final message = utf8.encode('{"version":"1.0.0"}');
    final signature = await algorithm.sign(message, keyPair: keyPair);

    final verified = await algorithm.verify(
      message,
      signature: signature,
    );
    expect(verified, isTrue);

    // Tampered message
    final tampered = utf8.encode('{"version":"1.0.1"}');
    final verifiedTampered = await algorithm.verify(
      tampered,
      signature: signature,
    );
    expect(verifiedTampered, isFalse);
  });

  test('HMAC-SHA256 generate and verify', () {
    final secretKey = utf8.encode('device-secret-key-1234567890123');
    final message = utf8.encode('{"rules":[]}');

    final hmac = crypto.Hmac(crypto.sha256, secretKey);
    final digest = hmac.convert(message).toString();

    final verifyHmac = crypto.Hmac(crypto.sha256, secretKey);
    final verifyDigest = verifyHmac.convert(message).toString();

    expect(digest, equals(verifyDigest));

    final tamperedMessage = utf8.encode('{"rules":[{"id":"hacked"}]}');
    final tamperedDigest = crypto.Hmac(crypto.sha256, secretKey).convert(tamperedMessage).toString();
    expect(digest, isNot(equals(tamperedDigest)));
  });
}
