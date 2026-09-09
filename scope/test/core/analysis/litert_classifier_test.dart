import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/storage/model_storage_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiteRtClassifier', () {
    test('initializes and falls back gracefully to heuristic classifier when asset loading fails', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '1',
        packageName: 'com.whatsapp',
        title: 'Mom',
        content: 'Hello, how are you?',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('msg'));
      expect(result.engineName, contains('fallback'));
      expect(result.score, equals(0.50));
    });

    test('fallback correctly categorizes bank alerts', () async {
      final classifier = LiteRtClassifier();
      
      final notif = AppNotification(
        id: '2',
        packageName: 'com.example.bank',
        title: 'Bank Alert',
        content: 'Your account XX3412 has been debited Rs. 2,000.',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);
      
      expect(result.category, equals('finance'));
      expect(result.engineName, contains('fallback'));
    });

    group('Dynamic Vocabulary Loading via ModelStorageManager', () {
      late Directory tempDir;
      late ModelStorageManager storageManager;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('litert_vocab_test_');
        storageManager = ModelStorageManager(baseDirectory: tempDir);
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('loads custom vocabulary from dynamic local storage', () async {
        final customVocab = '[PAD]\n[UNK]\n[CLS]\n[SEP]\nhello\ncustomtoken\n';
        await storageManager.saveVocabContent(customVocab);

        final classifier = LiteRtClassifier(storageManager: storageManager);

        final notif = AppNotification(
          id: 'custom-vocab-notif',
          packageName: 'com.whatsapp',
          title: 'Hello',
          content: 'customtoken',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );

        final result = await classifier.analyze(notif);
        expect(result, isNotNull);
        expect(classifier.tokenizer, isNotNull);
        expect(classifier.tokenizer!.vocab.containsKey('customtoken'), isTrue);
      });
    });
  });
}

