import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/asset_verifier.dart';
import 'package:scope/core/analysis/litert_classifier.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetVerifier Unit Tests', () {
    test('computes correct SHA-256 hash for raw bytes', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = AssetVerifier.computeHash(bytes);
      expect(hash, isNotEmpty);
      expect(hash.length, equals(64));
    });

    test('verifies ground-truth asset files from disk', () {
      final modelFile = File('assets/model.tflite');
      final rulesFile = File('assets/rules.json');
      final vocabFile = File('assets/vocab.txt');

      expect(modelFile.existsSync(), isTrue);
      expect(rulesFile.existsSync(), isTrue);
      expect(vocabFile.existsSync(), isTrue);

      final modelBytes = modelFile.readAsBytesSync();
      final rulesBytes = rulesFile.readAsBytesSync();
      final vocabBytes = vocabFile.readAsBytesSync();

      expect(AssetVerifier.verifyAsset('assets/model.tflite', modelBytes), isTrue);
      expect(AssetVerifier.verifyAsset('assets/rules.json', rulesBytes), isTrue);
      expect(AssetVerifier.verifyAsset('assets/vocab.txt', vocabBytes), isTrue);
    });

    test('throws AssetVerificationException on tampered model bytes', () {
      final modelBytes = File('assets/model.tflite').readAsBytesSync();
      final corruptedBytes = Uint8List.fromList(List<int>.from(modelBytes));
      // Tamper byte at index 10
      corruptedBytes[10] ^= 0xFF;

      expect(
        () => AssetVerifier.verifyAsset('assets/model.tflite', corruptedBytes),
        throwsA(isA<AssetVerificationException>()),
      );
    });

    test('throws AssetVerificationException for unregistered asset path', () {
      final bytes = Uint8List.fromList([10, 20, 30]);
      expect(
        () => AssetVerifier.verifyAsset('assets/unknown.bin', bytes),
        throwsA(isA<AssetVerificationException>()),
      );
    });
  });

  group('LiteRtClassifier Asset Integrity & Fallback Tests', () {
    test('tampered model bytes cause verification failure and trigger fallback heuristic', () async {
      final classifier = LiteRtClassifier();
      final modelBytes = File('assets/model.tflite').readAsBytesSync();
      final corruptedBytes = Uint8List.fromList(List<int>.from(modelBytes));
      corruptedBytes[0] ^= 0xFF; // Modify first byte

      await classifier.reinitialize(modelBytes: corruptedBytes);

      expect(classifier.isModelLoaded, isFalse);
      expect(classifier.verificationError, contains('SHA-256 integrity check failed'));

      final notif = AppNotification(
        id: 'corrupt_test_1',
        packageName: 'com.example.bank',
        title: 'Debit Alert',
        content: 'Rs. 500 debited from account xx1234',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await classifier.analyze(notif);

      expect(result.isFallback, isTrue);
      expect(result.score, equals(0.0));
      expect(result.category, equals('finance'));
      expect(result.matchedSignals.any((s) => s.contains('Asset verification failed')), isTrue);
    });
  });
}
