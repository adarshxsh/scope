import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scope/core/privacy/privacy_budget_engine.dart';
import 'package:scope/database/attention_database.dart';

/// Riverpod provider for the singleton database instance.
final databaseProvider = Provider<AttentionDatabase>((ref) {
  final isTest = Platform.environment.containsKey('FLUTTER_TEST');
  final db = isTest ? AttentionDatabase.inMemory() : AttentionDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Riverpod provider for the centralized PrivacyBudgetEngine.
final privacyBudgetEngineProvider = Provider<PrivacyBudgetEngine>((ref) {
  final db = ref.watch(databaseProvider);
  final engine = PrivacyBudgetEngine(db: db);
  engine.initialize();
  return engine;
});
