import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// In-memory holder for sensitive passphrase byte material that supports
/// zeroing out memory buffers upon completion of database initialization.
class PassphraseHolder {
  Uint8List? _bytes;

  PassphraseHolder(String passphrase) {
    _bytes = Uint8List.fromList(passphrase.codeUnits);
  }

  /// Retrieves the passphrase string from in-memory byte buffer.
  String get passphrase {
    if (_bytes == null) {
      throw StateError('PassphraseHolder has already been purged.');
    }
    return String.fromCharCodes(_bytes!);
  }

  /// Zeroes out the byte buffer in Dart heap memory and releases the reference.
  void purge() {
    if (_bytes != null) {
      _bytes!.fillRange(0, _bytes!.length, 0);
      _bytes = null;
    }
  }

  bool get isPurged => _bytes == null;
}

/// Secure Key Management service backed by platform secure storage
/// (Android Keystore and iOS Keychain via flutter_secure_storage).
class SecureKeyStorage {
  static const String passphraseKey = 'attention_os_db_passphrase';

  final FlutterSecureStorage _storage;

  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  /// Retrieves the existing 256-bit database passphrase key from platform secure storage,
  /// or generates and stores a new cryptographically random 256-bit passphrase.
  Future<String> getOrCreatePassphrase() async {
    String? passphrase = await _storage.read(key: passphraseKey);
    if (passphrase == null || passphrase.trim().isEmpty) {
      passphrase = generate256BitKey();
      await _storage.write(key: passphraseKey, value: passphrase);
    }
    return passphrase;
  }

  /// Retrieves the passphrase from platform secure storage if present.
  Future<String?> getPassphrase() async {
    return await _storage.read(key: passphraseKey);
  }

  /// Deletes the stored passphrase key from platform secure storage.
  Future<void> clearPassphrase() async {
    await _storage.delete(key: passphraseKey);
  }

  /// Generates a 256-bit (32 bytes) cryptographically random passphrase key
  /// formatted as a 64-character lowercase hexadecimal string.
  static String generate256BitKey() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
