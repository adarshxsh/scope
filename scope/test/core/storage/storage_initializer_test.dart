import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scope/core/storage/storage_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDocsDir;
  late Directory tempSupportDir;

  setUp(() async {
    tempDocsDir = await Directory.systemTemp.createTemp('test_docs_');
    tempSupportDir = await Directory.systemTemp.createTemp('test_support_');
  });

  tearDown(() async {
    if (tempDocsDir.existsSync()) {
      tempDocsDir.deleteSync(recursive: true);
    }
    if (tempSupportDir.existsSync()) {
      tempSupportDir.deleteSync(recursive: true);
    }
  });

  group('StorageInitializer Tests', () {
    test('migrates legacy file from documents to application support directory', () async {
      final legacyFile = File(p.join(tempDocsDir.path, 'rlhf_rules.json'));
      await legacyFile.writeAsString('[{"id":"rlhf-1","category":"Work","priority":"high"}]');

      final preparedFile = await StorageInitializer.prepareStorageFile(
        'rlhf_rules.json',
        overrideDocumentsDir: tempDocsDir,
        overrideSupportDir: tempSupportDir,
      );

      expect(preparedFile.path, equals(p.join(tempSupportDir.path, 'rlhf_rules.json')));
      expect(preparedFile.existsSync(), isTrue);
      expect(legacyFile.existsSync(), isFalse);
      expect(await preparedFile.readAsString(), contains('rlhf-1'));
    });

    test('migrates database and auxiliary sidecar files from documents directory', () async {
      final legacyDb = File(p.join(tempDocsDir.path, 'attention_os.db'));
      final legacyWal = File(p.join(tempDocsDir.path, 'attention_os.db-wal'));
      final legacyShm = File(p.join(tempDocsDir.path, 'attention_os.db-shm'));

      await legacyDb.writeAsString('sqlite db header mock');
      await legacyWal.writeAsString('wal data mock');
      await legacyShm.writeAsString('shm data mock');

      final preparedDb = await StorageInitializer.prepareStorageFile(
        'attention_os.db',
        overrideDocumentsDir: tempDocsDir,
        overrideSupportDir: tempSupportDir,
      );

      expect(preparedDb.path, equals(p.join(tempSupportDir.path, 'attention_os.db')));
      expect(preparedDb.existsSync(), isTrue);
      expect(legacyDb.existsSync(), isFalse);

      final targetWal = File(p.join(tempSupportDir.path, 'attention_os.db-wal'));
      final targetShm = File(p.join(tempSupportDir.path, 'attention_os.db-shm'));

      expect(targetWal.existsSync(), isTrue);
      expect(targetShm.existsSync(), isTrue);
      expect(legacyWal.existsSync(), isFalse);
      expect(legacyShm.existsSync(), isFalse);
    });

    test('creates new target file in support directory when no legacy file exists', () async {
      final preparedFile = await StorageInitializer.prepareStorageFile(
        'attention_os.db',
        overrideDocumentsDir: tempDocsDir,
        overrideSupportDir: tempSupportDir,
      );

      expect(preparedFile.path, equals(p.join(tempSupportDir.path, 'attention_os.db')));
      expect(preparedFile.existsSync(), isTrue);
    });

    test('applyNonBackupFlag executes without error on existing file', () async {
      final testFile = File(p.join(tempSupportDir.path, 'test_file.txt'));
      await testFile.writeAsString('test content');

      await expectLater(StorageInitializer.applyNonBackupFlag(testFile), completes);
    });
  });
}
