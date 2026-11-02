import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';

/// Riverpod provider for the DatabaseKeyManager instance.
final databaseKeyManagerProvider = Provider<DatabaseKeyManager>((ref) {
  final isTest = Platform.environment.containsKey('FLUTTER_TEST');
  final backend =
      isTest ? InMemoryKeyStorageBackend() : FlutterKeyStorageBackend();
  return DatabaseKeyManager(storageBackend: backend);
});

/// Riverpod provider for the singleton database instance.
final databaseProvider = Provider<AttentionDatabase>((ref) {
  final isTest = Platform.environment.containsKey('FLUTTER_TEST');
  if (isTest) {
    final db = AttentionDatabase.inMemory();
    ref.onDispose(() => db.close());
    return db;
  }
  final keyManager = ref.watch(databaseKeyManagerProvider);
  final db = AttentionDatabase.withKeyManager(keyManager: keyManager);
  ref.onDispose(() => db.close());
  return db;
});

