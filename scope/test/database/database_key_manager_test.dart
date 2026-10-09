import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:scope/database/database_key_manager.dart';

class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read({required String key, iOptions, aOptions, lOptions, webOptions, mOptions, wOptions}) async {
    return _storage[key];
  }

  @override
  Future<void> write({required String key, required String? value, iOptions, aOptions, lOptions, webOptions, mOptions, wOptions}) async {
    if (value != null) {
      _storage[key] = value;
    } else {
      _storage.remove(key);
    }
  }

  @override
  Future<bool> containsKey({required String key, iOptions, aOptions, lOptions, webOptions, mOptions, wOptions}) async {
    return _storage.containsKey(key);
  }

  @override
  Future<void> delete({required String key, iOptions, aOptions, lOptions, webOptions, mOptions, wOptions}) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll({iOptions, aOptions, lOptions, webOptions, mOptions, wOptions}) async {
    _storage.clear();
  }

  @override
  Future<Map<String, String>> readAll({iOptions, aOptions, lOptions, webOptions, mOptions, wOptions}) async {
    return Map.from(_storage);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('DatabaseKeyManager Unit Tests', () {
    test('generate256BitKey creates valid 64-character hex string (256 bits)', () {
      final key1 = DatabaseKeyManager.generate256BitKey();
      final key2 = DatabaseKeyManager.generate256BitKey();

      expect(key1.length, equals(64));
      expect(key2.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key1), isTrue);
      expect(key1, isNot(equals(key2)));
    });

    test('getOrCreateKey generates key on first access and reuses on subsequent access', () async {
      final fakeStorage = FakeSecureStorage();
      final manager = DatabaseKeyManager(secureStorage: fakeStorage);

      final key1 = await manager.getOrCreateKey();
      expect(key1.length, equals(64));

      final key2 = await manager.getOrCreateKey();
      expect(key2, equals(key1));
    });

    test('getOrCreateKey retrieves existing key from secure storage', () async {
      final fakeStorage = FakeSecureStorage();
      const existingKey = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      await fakeStorage.write(key: 'attention_db_encryption_key', value: existingKey);

      final manager = DatabaseKeyManager(secureStorage: fakeStorage);
      final key = await manager.getOrCreateKey();

      expect(key, equals(existingKey));
    });
  });
}
