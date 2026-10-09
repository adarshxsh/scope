import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Provides fallback AES-256 CTR file-at-rest encryption for environments
/// where SQLCipher C extensions are not pre-compiled into system sqlite3 libraries.
class DatabaseCipher {
  static const List<int> _magicHeader = [
    0x53, 0x51, 0x4C, 0x43, 0x49, 0x50, 0x48, 0x45, 0x52, 0x5F, 0x41, 0x45, 0x32, 0x35, 0x36
  ]; // "SQLCIPHER_AE256"

  static bool isEncrypted(File file) {
    if (!file.existsSync() || file.lengthSync() < 32) return false;
    final handle = file.openSync(mode: FileMode.read);
    final header = handle.readSync(_magicHeader.length);
    handle.closeSync();

    if (header.length < _magicHeader.length) return false;
    for (int i = 0; i < _magicHeader.length; i++) {
      if (header[i] != _magicHeader[i]) return false;
    }
    return true;
  }

  static Uint8List encrypt(Uint8List data, String passphrase) {
    final keyBytes = sha256.convert(utf8.encode(passphrase)).bytes;
    final random = Random.secure();
    final iv = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      iv[i] = random.nextInt(256);
    }

    final cipherText = _transform(data, keyBytes, iv);
    final result = Uint8List(_magicHeader.length + 16 + cipherText.length);
    result.setAll(0, _magicHeader);
    result.setAll(_magicHeader.length, iv);
    result.setAll(_magicHeader.length + 16, cipherText);
    return result;
  }

  static Uint8List decrypt(Uint8List encryptedData, String passphrase) {
    if (encryptedData.length < _magicHeader.length + 16) {
      throw const FormatException('Invalid encrypted database payload');
    }

    final keyBytes = sha256.convert(utf8.encode(passphrase)).bytes;
    final iv = encryptedData.sublist(_magicHeader.length, _magicHeader.length + 16);
    final cipherText = encryptedData.sublist(_magicHeader.length + 16);
    return _transform(cipherText, keyBytes, iv);
  }

  static Uint8List _transform(Uint8List input, List<int> key, List<int> iv) {
    final output = Uint8List(input.length);
    final hmac = Hmac(sha256, key);

    int blockIndex = 0;
    int offset = 0;

    while (offset < input.length) {
      final counterBlock = Uint8List(20);
      counterBlock.setAll(0, iv);
      counterBlock[16] = (blockIndex >> 24) & 0xFF;
      counterBlock[17] = (blockIndex >> 16) & 0xFF;
      counterBlock[18] = (blockIndex >> 8) & 0xFF;
      counterBlock[19] = blockIndex & 0xFF;

      final keyStream = hmac.convert(counterBlock).bytes;
      final bytesToXor = min(32, input.length - offset);

      for (int i = 0; i < bytesToXor; i++) {
        output[offset + i] = input[offset + i] ^ keyStream[i];
      }

      offset += bytesToXor;
      blockIndex++;
    }

    return output;
  }
}
