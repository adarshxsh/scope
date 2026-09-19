import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/sync/e2ee_sync_engine.dart';

void main() {
  group('SyncKeyManager & E2EESyncEngine Unit Tests', () {
    test('Key derivation produces deterministic keys from passphrase', () {
      final keys1 = SyncKeyManager.deriveKeysFromPassphrase('my-secret-passphrase-123');
      final keys2 = SyncKeyManager.deriveKeysFromPassphrase('my-secret-passphrase-123');

      expect(keys1['encKey'], equals(keys2['encKey']));
      expect(keys1['macKey'], equals(keys2['macKey']));
      expect(keys1['encKey']!.length, equals(32));
      expect(keys1['macKey']!.length, equals(32));
    });

    test('E2EESyncEngine encrypts and decrypts payloads correctly', () {
      final engine = E2EESyncEngine.fromPassphrase('secure-sync-key-2026');
      const plaintext = '{"notification_id":"notif-1","state":"REVIEWED"}';

      final payload = engine.encryptPayload(
        plaintextJson: plaintext,
        senderDeviceId: 'device-alpha',
        payloadType: 'review_state',
        vectorClockJson: '{"device-alpha":1}',
      );

      expect(payload.ciphertext, isNotEmpty);
      expect(payload.authTag, isNotEmpty);
      expect(payload.senderDeviceId, equals('device-alpha'));

      final decrypted = engine.decryptPayload(payload);
      expect(decrypted, equals(plaintext));
    });

    test('E2EESyncEngine throws E2EEDecryptionException when auth tag is tampered', () {
      final engine = E2EESyncEngine.fromPassphrase('secure-sync-key-2026');
      const plaintext = '{"notification_id":"notif-1","state":"REVIEWED"}';

      final payload = engine.encryptPayload(
        plaintextJson: plaintext,
        senderDeviceId: 'device-alpha',
        payloadType: 'review_state',
        vectorClockJson: '{"device-alpha":1}',
      );

      final tamperedPayload = EncryptedSyncPayload(
        ciphertext: payload.ciphertext,
        iv: payload.iv,
        authTag: 'tampered-auth-tag-value',
        senderDeviceId: payload.senderDeviceId,
        payloadType: payload.payloadType,
        timestamp: payload.timestamp,
        vectorClockJson: payload.vectorClockJson,
      );

      expect(
        () => engine.decryptPayload(tamperedPayload),
        throwsA(isA<E2EEDecryptionException>()),
      );
    });

    test('E2EESyncEngine enforces payload size cap guardrail', () {
      final engine = E2EESyncEngine.fromPassphrase('secure-sync-key-2026');
      final oversizedPlaintext = 'A' * 60000; // > 50 KB

      expect(
        () => engine.encryptPayload(
          plaintextJson: oversizedPlaintext,
          senderDeviceId: 'device-alpha',
          payloadType: 'review_state',
          vectorClockJson: '{}',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
