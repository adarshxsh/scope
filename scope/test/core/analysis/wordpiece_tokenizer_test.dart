import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';

void main() {
  group('WordPieceTokenizer Basic Tokenization', () {
    final Map<String, int> vocab = {
      '[PAD]': 0,
      '[UNK]': 1,
      '[CLS]': 2,
      '[SEP]': 3,
      'bank': 4,
      '##ing': 5,
      'alert': 6,
      'debit': 7,
      'urgent': 8,
      '##ed': 9,
    };

    late WordPieceTokenizer tokenizer;

    setUp(() {
      tokenizer = WordPieceTokenizer(vocab, maxSeqLength: 8);
    });

    test('tokenizes simple matched words with CLS, SEP, and PAD', () {
      final ids = tokenizer.tokenize('bank alert');
      // Expected tokens: [CLS], bank, alert, [SEP], [PAD], [PAD], [PAD], [PAD]
      expect(ids, equals([2, 4, 6, 3, 0, 0, 0, 0]));
    });

    test('tokenizes subwords using prefix ##', () {
      final ids = tokenizer.tokenize('banking');
      // 'banking' splits into 'bank' (4) + '##ing' (5)
      // Expected tokens: [CLS], bank, ##ing, [SEP], [PAD], [PAD], [PAD], [PAD]
      expect(ids, equals([2, 4, 5, 3, 0, 0, 0, 0]));
    });

    test('handles unknown characters using UNK', () {
      final ids = tokenizer.tokenize('unknownword');
      // Expected tokens: [CLS], [UNK], [SEP], [PAD], [PAD], [PAD], [PAD], [PAD]
      expect(ids, equals([2, 1, 3, 0, 0, 0, 0, 0]));
    });

    test('truncates text exceeding maxSeqLength', () {
      final ids = tokenizer.tokenize('bank alert debit urgent banking');
      // maxSeqLength is 8.
      // Expected: [CLS] (2), bank (4), alert (6), debit (7), urgent (8), bank (4), ##ing (5), [SEP] (3)
      // Overwrites index 7 with [SEP] (3).
      expect(ids.length, equals(8));
      expect(ids[0], equals(2)); // [CLS]
      expect(ids[7], equals(3)); // [SEP]
    });
  });

  group('WordPieceTokenizer Vocabulary Validation', () {
    test('throws VocabularyValidationException when required special token is missing', () {
      final invalidVocabMissingCls = {
        '[PAD]': 0,
        '[UNK]': 1,
        '[SEP]': 2,
        'hello': 3,
      };

      expect(
        () => WordPieceTokenizer(invalidVocabMissingCls),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('throws VocabularyValidationException when vocabulary is empty', () {
      expect(
        () => WordPieceTokenizer({}),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('throws VocabularyValidationException when size exceeds maxVocabSize', () {
      final largeVocab = <String, int>{
        '[PAD]': 0,
        '[UNK]': 1,
        '[CLS]': 2,
        '[SEP]': 3,
      };
      for (int i = 4; i < 15; i++) {
        largeVocab['word_$i'] = i;
      }

      expect(
        () => WordPieceTokenizer(largeVocab, maxVocabSize: 10),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('validates SHA-256 digest when provided in fromContent', () {
      const vocabContent = '[PAD]\n[UNK]\n[CLS]\n[SEP]\nbank\nalert';
      final validSha256 = sha256.convert(utf8.encode(vocabContent)).toString();
      const invalidSha256 = '0000000000000000000000000000000000000000000000000000000000000000';

      // Valid SHA-256 succeeds
      final tokenizer = WordPieceTokenizer.fromContent(
        vocabContent,
        expectedSha256: validSha256,
      );
      expect(tokenizer.vocab.length, equals(6));

      // Mismatched SHA-256 throws exception
      expect(
        () => WordPieceTokenizer.fromContent(
          vocabContent,
          expectedSha256: invalidSha256,
        ),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('dynamically uses reordered special token IDs from vocabulary mapping', () {
      // Reordered special tokens: [CLS] is 0, [SEP] is 1, [PAD] is 2, [UNK] is 3
      final reorderedVocab = {
        '[CLS]': 0,
        '[SEP]': 1,
        '[PAD]': 2,
        '[UNK]': 3,
        'test': 4,
      };

      final tokenizer = WordPieceTokenizer(reorderedVocab, maxSeqLength: 5);
      final ids = tokenizer.tokenize('test');

      // Expected: [CLS] (0), test (4), [SEP] (1), [PAD] (2), [PAD] (2)
      expect(ids, equals([0, 4, 1, 2, 2]));
    });
  });
}
