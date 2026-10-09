import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';

void main() {
  group('WordPieceTokenizer', () {
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

    group('Validation & Contracts', () {
      test('throws FormatException when fromLines is missing required special tokens', () {
        expect(
          () => WordPieceTokenizer.fromLines(['[PAD]', '[UNK]', '[CLS]']), // missing [SEP]
          throwsA(isA<FormatException>()),
        );
        expect(
          () => WordPieceTokenizer.fromLines(['[PAD]', '[UNK]', '[SEP]']), // missing [CLS]
          throwsA(isA<FormatException>()),
        );
        expect(
          () => WordPieceTokenizer.fromLines(['[PAD]', '[CLS]', '[SEP]']), // missing [UNK]
          throwsA(isA<FormatException>()),
        );
        expect(
          () => WordPieceTokenizer.fromLines(['[UNK]', '[CLS]', '[SEP]']), // missing [PAD]
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException when vocabulary lines are empty', () {
        expect(
          () => WordPieceTokenizer.fromLines([]),
          throwsA(isA<FormatException>()),
        );
      });

      test('uses verified vocabulary index for UNK rather than hardcoded index 100', () {
        final customVocab = {
          '[PAD]': 0,
          '[CLS]': 1,
          '[SEP]': 2,
          '[UNK]': 5, // Custom index != 100
        };
        final customTokenizer = WordPieceTokenizer(customVocab, maxSeqLength: 4);
        final ids = customTokenizer.tokenize('unknownword');
        // Expected: [CLS] (1), [UNK] (5 clamped to vocab.length-1=3), [SEP] (2), [PAD] (0)
        // Wait: customVocab.length is 4, maxIndex is 3, so index 5 gets clamped to 3.
        // If customVocab has length 10:
        final customVocab10 = {
          '[PAD]': 0,
          '[CLS]': 1,
          '[SEP]': 2,
          'a': 3,
          'b': 4,
          '[UNK]': 5, // Custom UNK index = 5
          'c': 6,
          'd': 7,
          'e': 8,
          'f': 9,
        };
        final customTokenizer10 = WordPieceTokenizer(customVocab10, maxSeqLength: 4);
        final ids10 = customTokenizer10.tokenize('unknownword');
        // Expected tokens: [CLS] (1), [UNK] (5), [SEP] (2), [PAD] (0)
        expect(ids10[1], equals(5));
        expect(ids10[1], isNot(equals(100)));
      });

      test('clamps generated token IDs to satisfy 0 <= id < vocab.length', () {
        final Map<String, int> vocabWithOutOfBounds = {
          '[PAD]': 0,
          '[UNK]': 1,
          '[CLS]': -5, // Negative out-of-bounds ID
          '[SEP]': 99, // Upper out-of-bounds ID (length is 5)
          'word': 2,
        };
        final customTokenizer = WordPieceTokenizer(vocabWithOutOfBounds, maxSeqLength: 4);
        final ids = customTokenizer.tokenize('word');

        // vocab length is 5. Valid IDs are 0..4.
        for (final id in ids) {
          expect(id, greaterThanOrEqualTo(0));
          expect(id, lessThan(vocabWithOutOfBounds.length));
        }
      });
    });
  });
}
