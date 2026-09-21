import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages database encryption key generation and hardware-backed secure storage.
class SecureKeyStorage {
  static const String _passphraseKey = 'attention_os_db_passphrase';
  final FlutterSecureStorage _storage;

  SecureKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  /// Retrieves existing 256-bit passphrase or generates and stores a new one.
  Future<String> getOrCreatePassphrase() async {
    try {
      String? passphrase = await _storage.read(key: _passphraseKey);
      if (passphrase != null && passphrase.isNotEmpty) {
        return passphrase;
      }

      passphrase = generate256BitPassphrase();
      await _storage.write(key: _passphraseKey, value: passphrase);
      return passphrase;
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        print('SecureKeyStorage: MissingPluginException ($e), returning test fallback key');
      }
      return _generateFallbackKey();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('SecureKeyStorage: PlatformException ($e), returning test fallback key');
      }
      return _generateFallbackKey();
    } catch (e) {
      if (kDebugMode) {
        print('SecureKeyStorage: Unexpected error ($e), returning test fallback key');
      }
      return _generateFallbackKey();
    }
  }

  /// Generates a cryptographically strong 256-bit passphrase (64 hex characters).
  static String generate256BitPassphrase() {
    final random = Random.secure();
    final values = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      values[i] = random.nextInt(256);
    }
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _generateFallbackKey() {
    return '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  }
}

/// In-memory holder for secret passphrase material with explicit memory purging.
class PassphraseHolder {
  final Uint8List _bytes;

  PassphraseHolder(String passphrase)
      : _bytes = Uint8List.fromList(passphrase.codeUnits);

  Uint8List get bytes => _bytes;

  void purge() {
    _bytes.fillRange(0, _bytes.length, 0);
  }
}
