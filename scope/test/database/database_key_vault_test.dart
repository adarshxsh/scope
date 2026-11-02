import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:scope/database/database_key_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseKeyVault Unit Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('getOrCreatePassphrase generates a 256-bit (64 hex char) random key on first call', () async {
      final vault = DatabaseKeyVault();
      final key = await vault.getOrCreatePassphrase();

      expect(key, isNotEmpty);
      expect(key.length, equals(64)); // 32 bytes * 2 hex chars/byte = 64 hex chars = 256 bits
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('getOrCreatePassphrase returns existing passphrase on subsequent calls', () async {
      final vault = DatabaseKeyVault();
      final key1 = await vault.getOrCreatePassphrase();
      final key2 = await vault.getOrCreatePassphrase();

      expect(key2, equals(key1));
    });

    test('generateAndSaveNewPassphrase creates and persists a new key', () async {
      final vault = DatabaseKeyVault();
      final key1 = await vault.getOrCreatePassphrase();
      final key2 = await vault.generateAndSaveNewPassphrase();

      expect(key2, isNot(equals(key1)));
      expect(key2.length, equals(64));

      final key3 = await vault.getOrCreatePassphrase();
      expect(key3, equals(key2));
    });

    test('clearKey removes passphrase from storage', () async {
      final vault = DatabaseKeyVault();
      final key1 = await vault.getOrCreatePassphrase();
      await vault.clearKey();

      final key2 = await vault.getOrCreatePassphrase();
      expect(key2, isNot(equals(key1)));
    });
  });
}
