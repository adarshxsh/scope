import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/database/attention_database.dart';

const _keystoreChannel = MethodChannel('com.scope.security/keystore');

/// Helper to fetch database passphrase asynchronously from AndroidKeyStore platform channel
/// or return a mock passphrase in unit/widget test environments.
Future<String> getDatabasePassphrase() async {
  final isTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (isTest) {
    return 'mock_test_passphrase_32bytes_long!';
  }
  try {
    final String? passphrase = await _keystoreChannel.invokeMethod<String>('getOrCreateDatabasePassphrase');
    return passphrase ?? '';
  } on MissingPluginException {
    return '';
  } on PlatformException {
    return '';
  }
}

/// Riverpod provider for the singleton database instance.
final databaseProvider = Provider<AttentionDatabase>((ref) {
  final isTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (isTest) {
    final db = AttentionDatabase.inMemory();
    ref.onDispose(() => db.close());
    return db;
  }

  final db = AttentionDatabase.encrypted(getDatabasePassphrase);
  ref.onDispose(() => db.close());
  return db;
});
