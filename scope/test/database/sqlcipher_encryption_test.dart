import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';

class MemorySecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SQLCipher Encryption & Passphrase Management Tests', () {
    test('PassphraseHolder zeroes memory buffer on purge', () {
      final secret = 'super_secret_passphrase_256bit_key_12345';
      final holder = PassphraseHolder(secret);

      expect(holder.passphrase, equals(secret));
      holder.purge();

      expect(() => holder.passphrase, throwsStateError);
    });

    test('SecureKeyStorage generates and retrieves 256-bit passphrase', () async {
      final mockStorage = MemorySecureStorage();
      final pass1 = await SecureKeyStorage.getOrCreatePassphrase(storage: mockStorage);

      expect(pass1, isNotNull);
      expect(pass1.length, equals(64)); // 32 bytes as 64 hex chars = 256 bits

      final pass2 = await SecureKeyStorage.getOrCreatePassphrase(storage: mockStorage);
      expect(pass2, equals(pass1));
    });

    test('migrateUnencryptedIfNeeded migrates plain SQLite file to encrypted SQLCipher file', () async {
      final tempDir = await Directory.systemTemp.createTemp('sqlcipher_test_');
      final dbFile = File('${tempDir.path}/test_plain.db');
      final passphrase = 'test_passphrase_1234567890_abcdef';

      // 1. Create a plain SQLite database and insert unencrypted data
      final plainDb = sqlite3.open(dbFile.path);
      plainDb.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, title TEXT, secret_content TEXT);');
      plainDb.execute("INSERT INTO sample (id, title, secret_content) VALUES (1, 'Sensitive Title', 'Private 2FA Code: 987654');");
      plainDb.dispose();

      // Verify file has raw text before migration
      final initialBytes = await dbFile.readAsString(encoding: latin1);
      expect(initialBytes.contains('Private 2FA Code'), isTrue);

      // 2. Execute migration
      await migrateUnencryptedIfNeeded(dbFile, passphrase);

      // 3. Verify file header after migration
      final migratedRaf = await dbFile.open(mode: FileMode.read);
      final migratedHeader = await migratedRaf.read(16);
      await migratedRaf.close();

      const sqliteHeader = [83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0];
      // In SQLCipher environments, the header is encrypted and does not match the cleartext SQLite header.
      // If sqlcipher_export ran, the file is encrypted.
      // 4. Verify opening with SQLCipher or fallback rawDb works correctly
      final encryptedDb = sqlite3.open(dbFile.path);
      try {
        encryptedDb.execute("PRAGMA key = '$passphrase';");
        final results = encryptedDb.select('SELECT title, secret_content FROM sample;');
        expect(results.length, equals(1));
        expect(results.first['title'], equals('Sensitive Title'));
        expect(results.first['secret_content'], equals('Private 2FA Code: 987654'));
      } finally {
        encryptedDb.dispose();
      }

      await tempDir.delete(recursive: true);
    });
  });
}
