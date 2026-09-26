import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/storage/storage_migration.dart';

void main() {
  late Directory tempDocsDir;
  late Directory tempSupportDir;

  setUp(() async {
    StorageMigration.resetMigrationState();
    tempDocsDir = await Directory.systemTemp.createTemp('legacy_docs_');
    tempSupportDir = await Directory.systemTemp.createTemp('target_support_');
  });

  tearDown(() async {
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
    if (await tempSupportDir.exists()) {
      await tempSupportDir.delete(recursive: true);
    }
  });

  group('StorageMigration Unit Tests', () {
    test('Migrates legacy database and rule files from documents to support directory', () async {
      final legacyDb = File(p.join(tempDocsDir.path, 'attention_os.db'));
      final legacyRules = File(p.join(tempDocsDir.path, 'rlhf_rules.json'));
      final legacyJournal = File(p.join(tempDocsDir.path, 'attention_os.db-journal'));

      await legacyDb.writeAsString('sqlite-db-data');
      await legacyRules.writeAsString('[{"id": "rlhf-1"}]');
      await legacyJournal.writeAsString('journal-data');

      expect(await legacyDb.exists(), isTrue);
      expect(await legacyRules.exists(), isTrue);
      expect(await legacyJournal.exists(), isTrue);

      await StorageMigration.migrateLegacyFiles(
        customDocumentsDir: tempDocsDir,
        customSupportDir: tempSupportDir,
      );

      // Legacy files should be removed
      expect(await legacyDb.exists(), isFalse);
      expect(await legacyRules.exists(), isFalse);
      expect(await legacyJournal.exists(), isFalse);

      // Target files should exist with correct content
      final targetDb = File(p.join(tempSupportDir.path, 'attention_os.db'));
      final targetRules = File(p.join(tempSupportDir.path, 'rlhf_rules.json'));
      final targetJournal = File(p.join(tempSupportDir.path, 'attention_os.db-journal'));

      expect(await targetDb.exists(), isTrue);
      expect(await targetDb.readAsString(), equals('sqlite-db-data'));

      expect(await targetRules.exists(), isTrue);
      expect(await targetRules.readAsString(), equals('[{"id": "rlhf-1"}]'));

      expect(await targetJournal.exists(), isTrue);
      expect(await targetJournal.readAsString(), equals('journal-data'));
    });

    test('Cleans up legacy files when target files already exist in support directory', () async {
      final legacyRules = File(p.join(tempDocsDir.path, 'rlhf_rules.json'));
      await legacyRules.writeAsString('[{"id": "old-rlhf"}]');

      final targetRules = File(p.join(tempSupportDir.path, 'rlhf_rules.json'));
      await targetRules.writeAsString('[{"id": "new-rlhf"}]');

      await StorageMigration.migrateLegacyFiles(
        customDocumentsDir: tempDocsDir,
        customSupportDir: tempSupportDir,
      );

      // Legacy file should be deleted
      expect(await legacyRules.exists(), isFalse);

      // Target file should retain its existing content
      expect(await targetRules.readAsString(), equals('[{"id": "new-rlhf"}]'));
    });
  });
}
