import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/storage/storage_migration.dart';

void main() {
  late Directory tempDir;
  late Directory docsDir;
  late Directory supportDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_migration_test_');
    docsDir = Directory(p.join(tempDir.path, 'Documents'));
    supportDir = Directory(p.join(tempDir.path, 'ApplicationSupport'));
    await docsDir.create(recursive: true);
    await supportDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StorageMigration Unit Tests', () {
    test('moves legacy attention_os.db and rlhf_rules.json from Documents to Application Support', () async {
      final legacyDb = File(p.join(docsDir.path, 'attention_os.db'));
      final legacyRules = File(p.join(docsDir.path, 'rlhf_rules.json'));

      await legacyDb.writeAsString('sqlite db content');
      await legacyRules.writeAsString('[{"id": "rlhf-1"}]');

      expect(await legacyDb.exists(), isTrue);
      expect(await legacyRules.exists(), isTrue);

      final targetDb = File(p.join(supportDir.path, 'attention_os.db'));
      final targetRules = File(p.join(supportDir.path, 'rlhf_rules.json'));

      expect(await targetDb.exists(), isFalse);
      expect(await targetRules.exists(), isFalse);

      await StorageMigration.migrateLegacyFiles(
        docsDir: docsDir,
        supportDir: supportDir,
      );

      // Verify files moved to target
      expect(await targetDb.exists(), isTrue);
      expect(await targetRules.exists(), isTrue);
      expect(await targetDb.readAsString(), equals('sqlite db content'));
      expect(await targetRules.readAsString(), equals('[{"id": "rlhf-1"}]'));

      // Verify legacy files removed
      expect(await legacyDb.exists(), isFalse);
      expect(await legacyRules.exists(), isFalse);
    });

    test('does not overwrite existing target file if legacy file exists', () async {
      final legacyDb = File(p.join(docsDir.path, 'attention_os.db'));
      final targetDb = File(p.join(supportDir.path, 'attention_os.db'));

      await legacyDb.writeAsString('old content');
      await targetDb.writeAsString('new content');

      await StorageMigration.migrateLegacyFiles(
        docsDir: docsDir,
        supportDir: supportDir,
      );

      // Target should preserve new content
      expect(await targetDb.readAsString(), equals('new content'));
    });

    test('handles missing legacy files gracefully without error', () async {
      await StorageMigration.migrateLegacyFiles(
        docsDir: docsDir,
        supportDir: supportDir,
      );

      final targetDb = File(p.join(supportDir.path, 'attention_os.db'));
      expect(await targetDb.exists(), isFalse);
    });

    test('handles identical docsDir and supportDir without error', () async {
      final legacyDb = File(p.join(docsDir.path, 'attention_os.db'));
      await legacyDb.writeAsString('db content');

      await StorageMigration.migrateLegacyFiles(
        docsDir: docsDir,
        supportDir: docsDir,
      );

      expect(await legacyDb.exists(), isTrue);
      expect(await legacyDb.readAsString(), equals('db content'));
    });
  });
}
