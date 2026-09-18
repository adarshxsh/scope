import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/vocab_validator.dart';

void main() {
  group('VocabValidator', () {
    const validVocabContent = '[PAD]\n[UNK]\n[CLS]\n[SEP]\n[MASK]\nalert\nbank';
    final String validHash = VocabValidator.computeHash(validVocabContent);

    final Map<String, int> validVocabMap = {
      '[PAD]': 0,
      '[UNK]': 1,
      '[CLS]': 2,
      '[SEP]': 3,
      '[MASK]': 4,
      'alert': 5,
      'bank': 6,
    };

    test('validates correct SHA-256 digest successfully', () {
      expect(
        () => VocabValidator.validate(validVocabContent, expectedHash: validHash),
        returnsNormally,
      );
    });

    test('rejects mismatched SHA-256 digest by throwing VocabularyValidationException', () {
      const corruptedContent = '[PAD]\n[UNK]\n[CLS]\n[SEP]\n[MASK]\ncorrupted_word';
      expect(
        () => VocabValidator.validate(corruptedContent, expectedHash: validHash),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('rejects line counts out of bounds', () {
      expect(
        () => VocabValidator.validate('', expectedHash: VocabValidator.computeHash('')),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('validates mandatory special tokens map successfully', () {
      expect(
        () => VocabValidator.validateSpecialTokens(validVocabMap),
        returnsNormally,
      );
    });

    test('throws VocabularyValidationException when mandatory special token is missing', () {
      final missingTokenMap = {
        '[PAD]': 0,
        '[UNK]': 1,
        '[CLS]': 2,
        '[SEP]': 3,
        // missing [MASK]
      };
      expect(
        () => VocabValidator.validateSpecialTokens(missingTokenMap),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('throws VocabularyValidationException when special token index is negative or out of bounds', () {
      final invalidIndexMap = {
        '[PAD]': -1,
        '[UNK]': 1,
        '[CLS]': 2,
        '[SEP]': 3,
        '[MASK]': 4,
      };
      expect(
        () => VocabValidator.validateSpecialTokens(invalidIndexMap),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('execution overhead is within 2 milliseconds constraint', () {
      final stopwatch = Stopwatch()..start();
      VocabValidator.validate(validVocabContent, expectedHash: validHash);
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThanOrEqualTo(2));
    });
  });
}
