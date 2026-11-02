import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/storage/backup_exclusion.dart';
import 'package:scope/core/storage/storage_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRootDir;
  late Directory legacyDir;
  late Directory targetDir;

  setUp(() async {
    tempRootDir = await Directory.systemTemp.createTemp('storage_migration_test_');
    legacyDir = Directory(p.join(tempRootDir.path, 'Documents'));
    targetDir = Directory(p.join(tempRootDir.path, 'ApplicationSupport'));
    await legacyDir.create(recursive: true);
    await targetDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tempRootDir.exists()) {
      await tempRootDir.delete(recursive: true);
    }
  });

  group('StorageMigrator', () {
    test('migrates database and custom rules from Documents to Application Support', () async {
      final legacyDb = File(p.join(legacyDir.path, 'attention_os.db'));
      await legacyDb.writeAsString('SQLITE_DUMMY_DATA');

      final legacyRules = File(p.join(legacyDir.path, 'rlhf_rules.json'));
      final sampleRules = [
        {
          'id': 'rlhf-1',
          'category': 'Work',
          'priority': 'high',
          'conditions': {
            'packages': ['com.slack'],
            'keywords': ['urgent'],
            'title_keywords': [],
          }
        }
      ];
      await legacyRules.writeAsString(json.encode(sampleRules));

      expect(await legacyDb.exists(), isTrue);
      expect(await legacyRules.exists(), isTrue);

      await StorageMigrator.migrate(
        customLegacyDir: legacyDir,
        customTargetDir: targetDir,
      );

      final targetDb = File(p.join(targetDir.path, 'attention_os.db'));
      final targetRules = File(p.join(targetDir.path, 'rlhf_rules.json'));

      expect(await targetDb.exists(), isTrue);
      expect(await targetDb.readAsString(), equals('SQLITE_DUMMY_DATA'));

      expect(await targetRules.exists(), isTrue);
      final readRules = json.decode(await targetRules.readAsString()) as List;
      expect(readRules.length, equals(1));
      expect(readRules.first['id'], equals('rlhf-1'));

      // Legacy files should be deleted after successful migration
      expect(await legacyDb.exists(), isFalse);
      expect(await legacyRules.exists(), isFalse);
    });

    test('handles file conflicts when target file already exists in Application Support', () async {
      final legacyDb = File(p.join(legacyDir.path, 'attention_os.db'));
      await legacyDb.writeAsString('OLD_LEGACY_DB');

      final targetDb = File(p.join(targetDir.path, 'attention_os.db'));
      await targetDb.writeAsString('NEW_TARGET_DB');

      await StorageMigrator.migrate(
        customLegacyDir: legacyDir,
        customTargetDir: targetDir,
      );

      // Target DB should remain intact and legacy DB cleaned up
      expect(await targetDb.exists(), isTrue);
      expect(await targetDb.readAsString(), equals('NEW_TARGET_DB'));
      expect(await legacyDb.exists(), isFalse);
    });

    test('handles corrupt legacy files gracefully during integrity check', () async {
      final legacyRules = File(p.join(legacyDir.path, 'rlhf_rules.json'));
      await legacyRules.writeAsString('{INVALID_JSON_CORRUPT');

      await StorageMigrator.migrate(
        customLegacyDir: legacyDir,
        customTargetDir: targetDir,
      );

      final targetRules = File(p.join(targetDir.path, 'rlhf_rules.json'));
      expect(await targetRules.exists(), isFalse);
    });
  });

  group('BackupExclusionService', () {
    test('excludeFromBackup completes safely on test platform', () async {
      final testFile = File(p.join(targetDir.path, 'test_file.txt'));
      await testFile.writeAsString('test');

      final result = await BackupExclusionService.excludeFromBackup(testFile.path);
      expect(result, isTrue);
    });
  });
}
