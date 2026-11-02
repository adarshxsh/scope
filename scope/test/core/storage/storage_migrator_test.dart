import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:scope/core/storage/backup_exclusion_helper.dart';
import 'package:scope/core/storage/storage_migrator.dart';

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String docsPath;
  final String supportPath;

  FakePathProviderPlatform(this.docsPath, this.supportPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocsDir;
  late Directory tempSupportDir;
  late FakePathProviderPlatform fakePathProvider;
  final List<String> excludedPaths = [];

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp('test_docs_');
    tempSupportDir = await Directory.systemTemp.createTemp('test_support_');
    fakePathProvider = FakePathProviderPlatform(tempDocsDir.path, tempSupportDir.path);
    PathProviderPlatform.instance = fakePathProvider;
    excludedPaths.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('scope/backup_protection'),
      (MethodCall call) async {
        if (call.method == 'excludeFromBackup') {
          final args = call.arguments as Map;
          final path = args['path'] as String;
          excludedPaths.add(path);
          return true;
        }
        return false;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('scope/backup_protection'),
      null,
    );
    if (await tempDocsDir.exists()) {
      await tempDocsDir.delete(recursive: true);
    }
    if (await tempSupportDir.exists()) {
      await tempSupportDir.delete(recursive: true);
    }
  });

  test('StorageMigrator transfers legacy files from Documents to Application Support and sets backup exclusion', () async {
    // 1. Create legacy files in Documents directory
    final legacyDb = File(p.join(tempDocsDir.path, 'attention_os.db'));
    final legacyWal = File(p.join(tempDocsDir.path, 'attention_os.db-wal'));
    final legacyRules = File(p.join(tempDocsDir.path, 'rlhf_rules.json'));

    await legacyDb.writeAsString('sqlite-db-data');
    await legacyWal.writeAsString('sqlite-wal-data');
    await legacyRules.writeAsString('[{"id":"rlhf-1"}]');

    expect(await legacyDb.exists(), true);
    expect(await legacyWal.exists(), true);
    expect(await legacyRules.exists(), true);

    // 2. Perform migration
    await StorageMigrator.migrate();

    // 3. Check legacy files are removed from Documents
    expect(await legacyDb.exists(), false);
    expect(await legacyWal.exists(), false);
    expect(await legacyRules.exists(), false);

    // 4. Check files exist in Application Support
    final migratedDb = File(p.join(tempSupportDir.path, 'attention_os.db'));
    final migratedWal = File(p.join(tempSupportDir.path, 'attention_os.db-wal'));
    final migratedRules = File(p.join(tempSupportDir.path, 'rlhf_rules.json'));

    expect(await migratedDb.exists(), true);
    expect(await migratedDb.readAsString(), 'sqlite-db-data');
    expect(await migratedWal.exists(), true);
    expect(await migratedWal.readAsString(), 'sqlite-wal-data');
    expect(await migratedRules.exists(), true);
    expect(await migratedRules.readAsString(), '[{"id":"rlhf-1"}]');

    // 5. Check backup exclusion was invoked on files
    expect(excludedPaths.contains(migratedDb.path), true);
    expect(excludedPaths.contains(migratedWal.path), true);
    expect(excludedPaths.contains(migratedRules.path), true);
  });

  test('BackupExclusionHelper fails gracefully when channel is missing or throws error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('scope/backup_protection'),
      (MethodCall call) async {
        throw PlatformException(code: 'UNAVAILABLE', message: 'Channel error');
      },
    );

    final result = await BackupExclusionHelper.excludeFromBackup('/some/fake/file');
    expect(result, false);
  });
}
