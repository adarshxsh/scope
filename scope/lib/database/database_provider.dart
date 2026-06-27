import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/database/attention_database.dart';

/// Riverpod provider for the singleton database instance.
final databaseProvider = Provider<AttentionDatabase>((ref) {
  final isTest = Platform.environment.containsKey('FLUTTER_TEST');
  final db = isTest ? AttentionDatabase.inMemory() : AttentionDatabase();
  ref.onDispose(() => db.close());
  return db;
});
