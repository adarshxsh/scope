import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/sync/crdt.dart';
import 'package:scope/core/sync/e2ee_sync_engine.dart';

void main() {
  group('E2EESyncEngine Encryption Tests', () {
    final engine = E2EESyncEngine.fromPassphrase('secure-sync-passphrase-123');

    test('Encrypts and decrypts sync payload cleanly', () {
      const delta = NotificationStateDelta(
        notificationId: 'notif_100',
        state: ReviewState.REVIEWED,
        originDeviceId: 'device_phone',
        vectorClock: VectorClock({'device_phone': 3}),
        timestamp: 1690000000000,
      );

      final encryptedPayload = engine.encryptPayload(
        plaintextJson: delta.toJson(),
        senderDeviceId: 'device_phone',
        payloadType: 'review_state',
        vectorClockJson: delta.vectorClock.toJson(),
      );

      // Verify zero-knowledge payload privacy: payload JSON contains no cleartext details
      expect(encryptedPayload.ciphertext, isNotEmpty);
      expect(encryptedPayload.ciphertext.contains('notif_100'), isFalse);
      expect(encryptedPayload.ciphertext.contains('REVIEWED'), isFalse);

      final decryptedJson = engine.decryptPayload(encryptedPayload);
      final restoredDelta = NotificationStateDelta.fromJson(decryptedJson);

      expect(restoredDelta.notificationId, equals('notif_100'));
      expect(restoredDelta.state, equals(ReviewState.REVIEWED));
      expect(restoredDelta.originDeviceId, equals('device_phone'));
      expect(restoredDelta.vectorClock.clock['device_phone'], equals(3));
    });

    test('Throws E2EEDecryptionException when authentication tag is tampered with', () {
      const delta = NotificationStateDelta(
        notificationId: 'notif_101',
        state: ReviewState.EXPIRED,
        originDeviceId: 'device_phone',
        vectorClock: VectorClock({'device_phone': 1}),
        timestamp: 1690000000000,
      );

      final encryptedPayload = engine.encryptPayload(
        plaintextJson: delta.toJson(),
        senderDeviceId: 'device_phone',
        payloadType: 'review_state',
        vectorClockJson: delta.vectorClock.toJson(),
      );

      // Tamper with authentication tag
      final tamperedPayload = EncryptedSyncPayload(
        ciphertext: encryptedPayload.ciphertext,
        iv: encryptedPayload.iv,
        authTag: 'invalid_auth_tag_123',
        senderDeviceId: encryptedPayload.senderDeviceId,
        payloadType: encryptedPayload.payloadType,
        timestamp: encryptedPayload.timestamp,
        vectorClockJson: encryptedPayload.vectorClockJson,
      );

      expect(() => engine.decryptPayload(tamperedPayload), throwsA(isA<E2EEDecryptionException>()));
    });

    test('Derives key from X25519 shared secret bytes', () {
      final privKey = SyncKeyManager.generateRandomKey();
      final pubKey = SyncKeyManager.generateRandomKey();

      final keys = SyncKeyManager.deriveKeysFromX25519SharedSecret(privKey, pubKey);

      expect(keys['encKey']!.length, equals(32));
      expect(keys['macKey']!.length, equals(32));

      final x25519Engine = E2EESyncEngine(
        encKey: keys['encKey']!,
        macKey: keys['macKey']!,
      );

      final payload = x25519Engine.encryptPayload(
        plaintextJson: '{"test": "x25519"}',
        senderDeviceId: 'device_tablet',
        payloadType: 'review_state',
        vectorClockJson: '{}',
      );

      final decrypted = x25519Engine.decryptPayload(payload);
      expect(decrypted, equals('{"test": "x25519"}'));
    });

    test('Verifies payload size limit (< 50 KB)', () {
      final payload = engine.encryptPayload(
        plaintextJson: '{"key": "value"}',
        senderDeviceId: 'device_1',
        payloadType: 'review_state',
        vectorClockJson: '{}',
      );

      expect(payload.sizeInBytes, lessThan(50 * 1024));
    });
  });
}
