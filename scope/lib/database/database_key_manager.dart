import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages secure key generation, key retrieval, and encryption guardrails for
/// the local SQLite database.
class DatabaseKeyManager {
  static const String _keyFileName = '.attention_os.key';
  static String? _overrideKey;
  String? _cachedKey;

  /// For testing or custom override injection
  static void setOverrideKey(String? key) {
    _overrideKey = key;
  }

  /// Retrieves or generates a secure 256-bit (64 hex char) encryption key
  /// for SQLite/SQLCipher database operations.
  Future<String> getDatabaseKey() async {
    if (_overrideKey != null && _overrideKey!.isNotEmpty) {
      return _overrideKey!;
    }
    if (_cachedKey != null) {
      return _cachedKey!;
    }

    try {
      final keyDirectory = await getApplicationSupportDirectory();
      final keyFile = File(p.join(keyDirectory.path, _keyFileName));

      if (await keyFile.exists()) {
        final existingKey = (await keyFile.readAsString()).trim();
        if (_isValidKey(existingKey)) {
          _cachedKey = existingKey;
          _logStructured('Key loaded successfully', {'keyLength': existingKey.length});
          return existingKey;
        } else {
          _logStructured('Existing key invalid, regenerating key', {'path': keyFile.path});
        }
      }

      // Generate a new cryptographically secure 256-bit key
      final newKey = _generateSecureKey();
      await keyDirectory.create(recursive: true);
      await keyFile.writeAsString(newKey, flush: true);

      // Restrict file permissions on POSIX systems if supported
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', keyFile.path]);
        } catch (_) {}
      }

      _cachedKey = newKey;
      _logStructured('New secure key generated and persisted', {'keyLength': newKey.length});
      return newKey;
    } catch (e) {
      // Fallback deterministic key derivation if file I/O is restricted
      _logStructured('Key generation file fallback triggered', {'error': e.toString()});
      final fallbackKey = _deriveFallbackKey();
      _cachedKey = fallbackKey;
      return fallbackKey;
    }
  }

  /// Generates a random 32-byte (256-bit) hex string using Random.secure()
  String _generateSecureKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Deterministic fallback key derivation when storage I/O fails
  String _deriveFallbackKey() {
    final seed = 'scope_attention_os_fallback_${Platform.operatingSystem}_${Platform.localHostname}';
    final bytes = utf8.encode(seed);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Validates that a key meets 256-bit hex complexity standards
  bool _isValidKey(String key) {
    if (key.length < 32) return false;
    final hexRegExp = RegExp(r'^[a-fA-F0-9]+$');
    return hexRegExp.hasMatch(key);
  }

  /// Clears cached key state (useful for test isolation)
  void clearCache() {
    _cachedKey = null;
  }

  /// Structured diagnostic logging without exposing cleartext PII or key material
  void _logStructured(String event, Map<String, dynamic> metadata) {
    if (kDebugMode || kProfileMode) {
      final timestamp = DateTime.now().toIso8601String();
      final sanitizedMetadata = Map<String, dynamic>.from(metadata);
      // Ensure no raw key or PII is ever logged
      sanitizedMetadata.remove('key');
      sanitizedMetadata.remove('rawKey');
      sanitizedMetadata.remove('title');
      sanitizedMetadata.remove('content');
      
      debugPrint('[DatabaseKeyManager][$timestamp] $event | $sanitizedMetadata');
    }
  }
}
