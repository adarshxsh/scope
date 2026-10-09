import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/database_key_manager.dart';

void main() {
  setUp(() async {
    final keyManager = DatabaseKeyManager();
    await keyManager.clearKey();
  });

  tearDown(() async {
    final keyManager = DatabaseKeyManager();
    await keyManager.clearKey();
  });

  group('DatabaseKeyManager Unit Tests', () {
    test('generates 256-bit AES key (64 hex characters) on initial creation', () async {
      final keyManager = DatabaseKeyManager();
      final key = await keyManager.getOrCreateKey();

      expect(key, isNotNull);
      expect(key.length, equals(64));
      expect(RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key), isTrue);
    });

    test('persists and returns identical key on subsequent retrievals', () async {
      final keyManager = DatabaseKeyManager();
      final key1 = await keyManager.getOrCreateKey();
      final key2 = await keyManager.getOrCreateKey();

      expect(key1, equals(key2));
    });

    test('respects test key override', () async {
      const customTestKey = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
      DatabaseKeyManager.setTestKey(customTestKey);

      final keyManager = DatabaseKeyManager();
      final key = await keyManager.getOrCreateKey();

      expect(key, equals(customTestKey));

      DatabaseKeyManager.setTestKey(null);
    });
  });
}
