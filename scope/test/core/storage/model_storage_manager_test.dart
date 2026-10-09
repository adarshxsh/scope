import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/storage/model_storage_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ModelStorageManager storageManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('model_storage_test_');
    storageManager = ModelStorageManager(baseDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ModelStorageManager Tests', () {
    test('initially reports no local model or vocab', () async {
      expect(await storageManager.hasLocalModel(), isFalse);
      expect(await storageManager.hasLocalVocab(), isFalse);
    });

    test('atomically saves model bytes and checks existence', () async {
      final mockModelBytes = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
      final savedFile = await storageManager.saveModelBytes(mockModelBytes);

      expect(await savedFile.exists(), isTrue);
      expect(await storageManager.hasLocalModel(), isTrue);

      final readBytes = await savedFile.readAsBytes();
      expect(readBytes, equals(mockModelBytes));
    });

    test('atomically saves vocab content and checks existence', () async {
      final mockVocabContent = '[PAD]\n[UNK]\n[CLS]\n[SEP]\nhello\nworld\n';
      final savedFile = await storageManager.saveVocabContent(mockVocabContent);

      expect(await savedFile.exists(), isTrue);
      expect(await storageManager.hasLocalVocab(), isTrue);

      final readContent = await savedFile.readAsString();
      expect(readContent, equals(mockVocabContent));
    });

    test('deletes local model and vocab individually', () async {
      await storageManager.saveModelBytes([1, 2, 3, 4]);
      await storageManager.saveVocabContent('test vocab');

      expect(await storageManager.hasLocalModel(), isTrue);
      expect(await storageManager.hasLocalVocab(), isTrue);

      await storageManager.deleteLocalModel();
      expect(await storageManager.hasLocalModel(), isFalse);
      expect(await storageManager.hasLocalVocab(), isTrue);

      await storageManager.deleteLocalVocab();
      expect(await storageManager.hasLocalVocab(), isFalse);
    });

    test('clearAll removes both model and vocab files', () async {
      await storageManager.saveModelBytes([1, 2, 3, 4]);
      await storageManager.saveVocabContent('test vocab');

      await storageManager.clearAll();

      expect(await storageManager.hasLocalModel(), isFalse);
      expect(await storageManager.hasLocalVocab(), isFalse);
    });

    test('handles empty or zero-byte file gracefully', () async {
      final modelFile = await storageManager.getModelFile();
      await modelFile.writeAsBytes([]); // 0 bytes

      expect(await storageManager.hasLocalModel(), isFalse);
    });

    test('loads local vocab content when available', () async {
      final mockVocab = '[PAD]\n[UNK]\n[CLS]\n[SEP]\ncustom_token\n';
      await storageManager.saveVocabContent(mockVocab);

      final content = await storageManager.loadVocabContent();
      expect(content, equals(mockVocab));
    });
  });
}
