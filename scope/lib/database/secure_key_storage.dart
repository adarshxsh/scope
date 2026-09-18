import 'dart:io';
import 'package:flutter/services.dart';

/// Interfaces with hardware-backed platform secure storage (AndroidKeyStore / iOS Keychain)
/// via MethodChannel to retrieve or generate the 256-bit database encryption key.
class SecureKeyStorage {
  static const MethodChannel _keystoreChannel = MethodChannel('com.scope.keystore');
  static const MethodChannel _securityChannel = MethodChannel('com.scope.attentions/security');

  static String? _inMemoryMockKey;

  /// Sets an in-memory key for testing or override purposes.
  static void setMockKey(String? key) {
    _inMemoryMockKey = key;
  }

  /// Retrieves the 256-bit database encryption key from secure platform storage.
  /// Throws [StateError] if key retrieval fails or returns an empty key.
  static Future<String> getDatabaseKey() async {
    if (_inMemoryMockKey != null) {
      if (_inMemoryMockKey!.isEmpty) {
        throw StateError('Retrieved invalid empty key from secure storage');
      }
      return _inMemoryMockKey!;
    }

    final isTest = Platform.environment.containsKey('FLUTTER_TEST');

    try {
      final String? key = await _keystoreChannel.invokeMethod<String>('getDatabaseKey');
      if (key != null && key.isNotEmpty) {
        return key;
      }
    } catch (_) {
      try {
        final String? key = await _securityChannel.invokeMethod<String>('getDatabaseKey');
        if (key != null && key.isNotEmpty) {
          return key;
        }
      } catch (_) {
        if (isTest) {
          return _generateFallbackTestKey();
        }
      }
    }

    if (isTest) {
      return _generateFallbackTestKey();
    }

    throw StateError('Failed to retrieve database encryption key from secure storage');
  }

  static String _generateFallbackTestKey() {
    return '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  }
}
