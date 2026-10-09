import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/storage/storage_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocDir;
  late Directory tempSuppDir;

  setUp(() async {
    StorageMigrator.resetForTesting();
    tempDocDir = await Directory.systemTemp.createTemp('legacy_doc_');
    tempSuppDir = await Directory.systemTemp.createTemp('target_supp_');
  });

  tearDown(() async {
    if (await tempDocDir.exists()) {
      await tempDocDir.delete(recursive: true);
    }
    if (await tempSuppDir.exists()) {
      await tempSuppDir.delete(recursive: true);
    }
  });

  test('StorageMigrator moves legacy attention_os.db and rlhf_rules.json to Application Support', () async {
    // 1. Setup legacy files in Documents
    final legacyDb = File(p.join(tempDocDir.path, 'attention_os.db'));
    await legacyDb.writeAsString('sqlite-database-dummy-content');

    final legacyRules = File(p.join(tempDocDir.path, 'rlhf_rules.json'));
    await legacyRules.writeAsString('[{"id": "rlhf-1", "category": "test"}]');

    final legacyWal = File(p.join(tempDocDir.path, 'attention_os.db-wal'));
    await legacyWal.writeAsString('wal-content');

    // 2. Perform migration
    await StorageMigrator.migrate(
      documentsDirOverride: tempDocDir,
      supportDirOverride: tempSuppDir,
    );

    // 3. Verify target files exist in Application Support
    final migratedDb = File(p.join(tempSuppDir.path, 'attention_os.db'));
    final migratedRules = File(p.join(tempSuppDir.path, 'rlhf_rules.json'));
    final migratedWal = File(p.join(tempSuppDir.path, 'attention_os.db-wal'));

    expect(await migratedDb.exists(), isTrue);
    expect(await migratedRules.exists(), isTrue);
    expect(await migratedWal.exists(), isTrue);

    expect(await migratedDb.readAsString(), equals('sqlite-database-dummy-content'));
    expect(await migratedRules.readAsString(), equals('[{"id": "rlhf-1", "category": "test"}]'));

    // 4. Verify legacy files were deleted from Documents
    expect(await legacyDb.exists(), isFalse);
    expect(await legacyRules.exists(), isFalse);
    expect(await legacyWal.exists(), isFalse);
  });

  test('StorageMigrator completes gracefully on fresh install with no legacy files', () async {
    await StorageMigrator.migrate(
      documentsDirOverride: tempDocDir,
      supportDirOverride: tempSuppDir,
    );

    expect(await tempSuppDir.exists(), isTrue);
    final entities = await tempSuppDir.list().toList();
    expect(entities, isEmpty);
  });

  test('StorageMigrator is idempotent when executed multiple times', () async {
    final legacyDb = File(p.join(tempDocDir.path, 'attention_os.db'));
    await legacyDb.writeAsString('db-content');

    // First migration
    await StorageMigrator.migrate(
      documentsDirOverride: tempDocDir,
      supportDirOverride: tempSuppDir,
    );

    expect(await File(p.join(tempSuppDir.path, 'attention_os.db')).exists(), isTrue);
    expect(await legacyDb.exists(), isFalse);

    // Second migration
    await StorageMigrator.migrate(
      documentsDirOverride: tempDocDir,
      supportDirOverride: tempSuppDir,
    );

    expect(await File(p.join(tempSuppDir.path, 'attention_os.db')).exists(), isTrue);
  });
}
