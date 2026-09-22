import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/database_key_manager.dart';

class MockSecureStorage implements SecureStorageWrapper {
  final Map<String, String> _storage = {};
  bool shouldThrowOnRead = false;
  bool shouldThrowOnWrite = false;

  @override
  Future<String?> read({required String key}) async {
    if (shouldThrowOnRead) {
      throw Exception('Hardware keystore unavailable');
    }
    return _storage[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (shouldThrowOnWrite) {
      throw Exception('Secure storage write failed');
    }
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    _storage.remove(key);
  }
}

void main() {
  group('DatabaseKeyManager Tests', () {
    late MockSecureStorage mockStorage;
    late DatabaseKeyManager keyManager;

    setUp(() {
      mockStorage = MockSecureStorage();
      keyManager = DatabaseKeyManager(mockStorage);
    });

    test('generates and persists a new 256-bit key when storage is empty', () async {
      final key = await keyManager.getOrCreateKey();
      expect(key, isNotNull);
      // 256-bit key formatted as hex string is 64 characters long
      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);

      // Verify key was persisted
      final storedKey = await mockStorage.read(key: 'attention_os_db_key');
      expect(storedKey, equals(key));
    });

    test('retrieves existing key from secure storage on subsequent runs', () async {
      const existingKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      await mockStorage.write(key: 'attention_os_db_key', value: existingKey);

      final fetchedKey = await keyManager.getOrCreateKey();
      expect(fetchedKey, equals(existingKey));
    });

    test('fails safely with DatabaseKeyException when secure storage read fails', () async {
      mockStorage.shouldThrowOnRead = true;
      expect(
        () => keyManager.getOrCreateKey(),
        throwsA(isA<DatabaseKeyException>()),
      );
    });

    test('fails safely with DatabaseKeyException when secure storage write fails', () async {
      mockStorage.shouldThrowOnWrite = true;
      expect(
        () => keyManager.getOrCreateKey(),
        throwsA(isA<DatabaseKeyException>()),
      );
    });

    test('clears stored key successfully', () async {
      await mockStorage.write(key: 'attention_os_db_key', value: 'some_key');
      await keyManager.clearKey();

      final storedKey = await mockStorage.read(key: 'attention_os_db_key');
      expect(storedKey, isNull);
    });
  });
}
