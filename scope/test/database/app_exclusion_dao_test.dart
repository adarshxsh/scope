import 'package:flutter_test/flutter_test.dart';
import 'package:scope/database/attention_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppExclusionsDao Unit Tests', () {
    late AttentionDatabase db;

    setUp(() {
      db = AttentionDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertExclusion inserts and retrieves entries correctly', () async {
      final entry = AppExclusionEntry(
        packageName: 'com.chase.sig.android',
        appName: 'Chase Mobile',
        category: 'banking',
        isExcluded: false,
        isDefault: true,
        updatedAt: DateTime.now(),
      );

      await db.appExclusionsDao.upsertExclusion(entry);

      final retrieved = await db.appExclusionsDao.getByPackage('com.chase.sig.android');
      expect(retrieved, isNotNull);
      expect(retrieved!.appName, equals('Chase Mobile'));
      expect(retrieved.isExcluded, isFalse);
      expect(retrieved.isDefault, isTrue);
    });

    test('upsertExclusion updates existing package entry', () async {
      final initial = AppExclusionEntry(
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        category: 'general',
        isExcluded: false,
        isDefault: false,
        updatedAt: DateTime.now(),
      );

      await db.appExclusionsDao.upsertExclusion(initial);

      final updated = initial.copyWith(isExcluded: true);
      await db.appExclusionsDao.upsertExclusion(updated);

      final retrieved = await db.appExclusionsDao.getByPackage('com.whatsapp');
      expect(retrieved, isNotNull);
      expect(retrieved!.isExcluded, isTrue);

      final all = await db.appExclusionsDao.getAll();
      expect(all.length, equals(1));
    });

    test('deleteExclusion and clearAll remove entries', () async {
      await db.appExclusionsDao.upsertExclusion(AppExclusionEntry(
        packageName: 'app.one',
        appName: 'App One',
        category: 'general',
        isExcluded: true,
        isDefault: false,
        updatedAt: DateTime.now(),
      ));

      await db.appExclusionsDao.upsertExclusion(AppExclusionEntry(
        packageName: 'app.two',
        appName: 'App Two',
        category: 'general',
        isExcluded: true,
        isDefault: false,
        updatedAt: DateTime.now(),
      ));

      expect((await db.appExclusionsDao.getAll()).length, equals(2));

      await db.appExclusionsDao.deleteExclusion('app.one');
      expect((await db.appExclusionsDao.getAll()).length, equals(1));

      await db.appExclusionsDao.clearAll();
      expect((await db.appExclusionsDao.getAll()), isEmpty);
    });
  });
}
