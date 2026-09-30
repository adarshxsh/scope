import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/database_key_manager.dart';

class FailingKeyStorage implements KeyStorage {
  @override
  Future<String?> readKey(String key) async {
    throw Exception('Keystore hardware module unnavailable');
  }

  @override
  Future<void> writeKey(String key, String value) async {
    throw Exception('Keystore write failed');
  }

  @override
  Future<void> deleteKey(String key) async {
    throw Exception('Keystore delete failed');
  }
}

void main() {
  group('DatabaseKeyManager Unit Tests', () {
    late InMemoryKeyStorage keyStorage;
    late DatabaseKeyManager keyManager;

    setUp(() {
      keyStorage = InMemoryKeyStorage();
      keyManager = DatabaseKeyManager(storage: keyStorage);
    });

    test('generates valid 256-bit hex key (64 characters)', () {
      final key = DatabaseKeyManager.generate256BitKey();
      expect(key, isNotNull);
      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('creates key on first access and persists it', () async {
      final key1 = await keyManager.getOrCreateKey();
      expect(key1.length, equals(64));

      // Second retrieval returns same key
      final key2 = await keyManager.getOrCreateKey();
      expect(key2, equals(key1));
    });

    test('deletes key from secure storage', () async {
      final key1 = await keyManager.getOrCreateKey();
      expect(key1, isNotNull);

      await keyManager.deleteKey();

      final key2 = await keyManager.getOrCreateKey();
      expect(key2, isNot(equals(key1)));
    });

    test('wraps storage exceptions gracefully', () async {
      final failingManager = DatabaseKeyManager(storage: FailingKeyStorage());
      expect(
        () => failingManager.getOrCreateKey(),
        throwsA(isA<SecureKeyStorageException>()),
      );
    });
  });
}
