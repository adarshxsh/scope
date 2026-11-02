import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PassphraseHolder {
  Uint8List? _buffer;

  PassphraseHolder(String passphrase) {
    _buffer = Uint8List.fromList(passphrase.codeUnits);
  }

  String get passphrase {
    if (_buffer == null) throw StateError('Passphrase has been purged.');
    return String.fromCharCodes(_buffer!);
  }

  void purge() {
    if (_buffer != null) {
      _buffer!.fillRange(0, _buffer!.length, 0);
      _buffer = null;
    }
  }
}

class SecureKeyStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _dbPassphraseKey = 'attention_os_db_passphrase';

  static Future<String> getOrCreatePassphrase({FlutterSecureStorage? storage}) async {
    final s = storage ?? _storage;
    String? passphrase = await s.read(key: _dbPassphraseKey);
    if (passphrase == null || passphrase.isEmpty) {
      final random = Random.secure();
      final values = List<int>.generate(32, (_) => random.nextInt(256));
      passphrase = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await s.write(key: _dbPassphraseKey, value: passphrase);
    }
    return passphrase;
  }
}
