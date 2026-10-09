import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/database/attention_database.dart';
import 'package:scope/database/secure_key_storage.dart';

/// Riverpod provider for SecureKeyStorage instance.
final secureKeyStorageProvider = Provider<SecureKeyStorage>((ref) {
  return SecureKeyStorage();
});

/// Riverpod provider for the singleton database instance.
final databaseProvider = Provider<AttentionDatabase>((ref) {
  final isTest = Platform.environment.containsKey('FLUTTER_TEST');
  final keyStorage = ref.watch(secureKeyStorageProvider);
  final db = isTest ? AttentionDatabase.inMemory() : AttentionDatabase.create(keyStorage: keyStorage);
  ref.onDispose(() => db.close());
  return db;
});
