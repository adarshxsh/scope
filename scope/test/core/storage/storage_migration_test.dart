import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/storage/storage_migration.dart';

void main() {
  late Directory tempDir;
  late Directory legacyDir;
  late Directory supportDir;

  setUp(() async {
    StorageMigrationService.resetForTest();
    tempDir = await Directory.systemTemp.createTemp('storage_migration_test_');
    legacyDir = Directory(p.join(tempDir.path, 'documents'))..createSync();
    supportDir = Directory(p.join(tempDir.path, 'app_support'))..createSync();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('relocates legacy database and rule files from documents to support directory', () async {
    final legacyDb = File(p.join(legacyDir.path, 'attention_os.db'));
    final legacyWal = File(p.join(legacyDir.path, 'attention_os.db-wal'));
    final legacyRules = File(p.join(legacyDir.path, 'rlhf_rules.json'));

    await legacyDb.writeAsString('db_content_123');
    await legacyWal.writeAsString('wal_content_456');
    await legacyRules.writeAsString('[{"id": "rlhf-1"}]');

    expect(await legacyDb.exists(), isTrue);
    expect(await legacyWal.exists(), isTrue);
    expect(await legacyRules.exists(), isTrue);

    await StorageMigrationService.migrateStorage(
      legacyDir: legacyDir,
      supportDir: supportDir,
      force: true,
    );

    expect(await legacyDb.exists(), isFalse);
    expect(await legacyWal.exists(), isFalse);
    expect(await legacyRules.exists(), isFalse);

    final targetDb = File(p.join(supportDir.path, 'attention_os.db'));
    final targetWal = File(p.join(supportDir.path, 'attention_os.db-wal'));
    final targetRules = File(p.join(supportDir.path, 'rlhf_rules.json'));

    expect(await targetDb.exists(), isTrue);
    expect(await targetDb.readAsString(), equals('db_content_123'));
    expect(await targetWal.exists(), isTrue);
    expect(await targetWal.readAsString(), equals('wal_content_456'));
    expect(await targetRules.exists(), isTrue);
    expect(await targetRules.readAsString(), equals('[{"id": "rlhf-1"}]'));
  });

  test('migration is idempotent on subsequent runs', () async {
    final legacyRules = File(p.join(legacyDir.path, 'rlhf_rules.json'));
    await legacyRules.writeAsString('[{"id": "rlhf-2"}]');

    await StorageMigrationService.migrateStorage(
      legacyDir: legacyDir,
      supportDir: supportDir,
      force: true,
    );

    final targetRules = File(p.join(supportDir.path, 'rlhf_rules.json'));
    expect(await targetRules.readAsString(), equals('[{"id": "rlhf-2"}]'));

    // Second migration run
    await StorageMigrationService.migrateStorage(
      legacyDir: legacyDir,
      supportDir: supportDir,
      force: true,
    );

    expect(await targetRules.readAsString(), equals('[{"id": "rlhf-2"}]'));
  });

  test('cleans up legacy file if target file already exists in support directory', () async {
    final legacyDb = File(p.join(legacyDir.path, 'attention_os.db'));
    final targetDb = File(p.join(supportDir.path, 'attention_os.db'));

    await legacyDb.writeAsString('old_legacy_db');
    await targetDb.writeAsString('new_target_db');

    await StorageMigrationService.migrateStorage(
      legacyDir: legacyDir,
      supportDir: supportDir,
      force: true,
    );

    expect(await legacyDb.exists(), isFalse);
    expect(await targetDb.exists(), isTrue);
    expect(await targetDb.readAsString(), equals('new_target_db'));
  });

  test('handles fresh installation gracefully when no legacy files exist', () async {
    await StorageMigrationService.migrateStorage(
      legacyDir: legacyDir,
      supportDir: supportDir,
      force: true,
    );

    expect(await supportDir.exists(), isTrue);
    expect(supportDir.listSync().isEmpty, isTrue);
  });
}
