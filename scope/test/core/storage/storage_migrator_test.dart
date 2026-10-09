import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/storage/backup_exclusion_helper.dart';
import 'package:scope/core/storage/storage_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory mockDocsDir;
  late Directory mockSupportDir;

  setUp(() async {
    StorageMigrator.resetForTest();
    tempDir = await Directory.systemTemp.createTemp('storage_migrator_test_');
    mockDocsDir = Directory(p.join(tempDir.path, 'documents'));
    mockSupportDir = Directory(p.join(tempDir.path, 'support'));

    await mockDocsDir.create(recursive: true);
    await mockSupportDir.create(recursive: true);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return mockDocsDir.path;
        }
        if (methodCall.method == 'getApplicationSupportDirectory') {
          return mockSupportDir.path;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('StorageMigrator moves legacy database and rule files to Application Support directory', () async {
    final legacyDb = File(p.join(mockDocsDir.path, 'attention_os.db'));
    final legacyWal = File(p.join(mockDocsDir.path, 'attention_os.db-wal'));
    final legacyShm = File(p.join(mockDocsDir.path, 'attention_os.db-shm'));
    final legacyRules = File(p.join(mockDocsDir.path, 'rlhf_rules.json'));

    await legacyDb.writeAsString('SQLITE_TEST_DB_CONTENT');
    await legacyWal.writeAsString('SQLITE_TEST_WAL_CONTENT');
    await legacyShm.writeAsString('SQLITE_TEST_SHM_CONTENT');
    await legacyRules.writeAsString('[{"id":"rlhf-123","category":"test","priority":"high"}]');

    expect(await legacyDb.exists(), isTrue);
    expect(await legacyRules.exists(), isTrue);

    final supportDir = await StorageMigrator.getSupportDirectoryWithMigration();

    expect(supportDir.path, equals(mockSupportDir.path));

    final targetDb = File(p.join(mockSupportDir.path, 'attention_os.db'));
    final targetWal = File(p.join(mockSupportDir.path, 'attention_os.db-wal'));
    final targetShm = File(p.join(mockSupportDir.path, 'attention_os.db-shm'));
    final targetRules = File(p.join(mockSupportDir.path, 'rlhf_rules.json'));

    expect(await targetDb.exists(), isTrue);
    expect(await targetDb.readAsString(), equals('SQLITE_TEST_DB_CONTENT'));

    expect(await targetWal.exists(), isTrue);
    expect(await targetWal.readAsString(), equals('SQLITE_TEST_WAL_CONTENT'));

    expect(await targetShm.exists(), isTrue);
    expect(await targetShm.readAsString(), equals('SQLITE_TEST_SHM_CONTENT'));

    expect(await targetRules.exists(), isTrue);
    expect(await targetRules.readAsString(), equals('[{"id":"rlhf-123","category":"test","priority":"high"}]'));

    expect(await legacyDb.exists(), isFalse);
    expect(await legacyWal.exists(), isFalse);
    expect(await legacyShm.exists(), isFalse);
    expect(await legacyRules.exists(), isFalse);
  });

  test('StorageMigrator removes legacy files if target files already exist in Application Support', () async {
    final targetDb = File(p.join(mockSupportDir.path, 'attention_os.db'));
    await targetDb.writeAsString('NEW_SUPPORT_DB_CONTENT');

    final legacyDb = File(p.join(mockDocsDir.path, 'attention_os.db'));
    await legacyDb.writeAsString('STALE_DOCS_DB_CONTENT');

    await StorageMigrator.getSupportDirectoryWithMigration();

    expect(await targetDb.readAsString(), equals('NEW_SUPPORT_DB_CONTENT'));
    expect(await legacyDb.exists(), isFalse);
  });

  test('BackupExclusionHelper handles platform channel calls gracefully', () async {
    await expectLater(
      BackupExclusionHelper.excludeFromBackup(p.join(mockSupportDir.path, 'attention_os.db')),
      completes,
    );
  });
}
