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

    group('Schema Validation & Dynamic Token Resolution', () {
      final validLines = [
        '[PAD]',
        '[UNK]',
        '[CLS]',
        '[SEP]',
        'bank',
        'alert',
      ];

      test('fromLines verifies SHA-256 hash when provided and succeeds on match', () {
        // Hash for '[PAD]\n[UNK]\n[CLS]\n[SEP]\nbank\nalert'
        const hash = '28ed6223b663fde5aeab80cfb6ca284797318430a3da258186aa4f36868e5303';
        final tok = WordPieceTokenizer.fromLines(validLines, expectedHash: hash);
        expect(tok.padId, equals(0));
        expect(tok.unkId, equals(1));
        expect(tok.clsId, equals(2));
        expect(tok.sepId, equals(3));
      });

      test('fromLines throws VocabularyValidationException on SHA-256 hash mismatch', () {
        expect(
          () => WordPieceTokenizer.fromLines(
            validLines,
            expectedHash: '0000000000000000000000000000000000000000000000000000000000000000',
          ),
          throwsA(
            isA<VocabularyValidationException>().having(
              (e) => e.message,
              'message',
              contains('SHA-256 digest mismatch'),
            ),
          ),
        );
      });

      test('fromLines throws VocabularyValidationException when line count is below minLines', () {
        final shortLines = ['[PAD]', '[UNK]'];
        expect(
          () => WordPieceTokenizer.fromLines(shortLines, minLines: 4),
          throwsA(
            isA<VocabularyValidationException>().having(
              (e) => e.message,
              'message',
              contains('out of bounds'),
            ),
          ),
        );
      });

      test('fromLines throws VocabularyValidationException when line count exceeds maxLines', () {
        expect(
          () => WordPieceTokenizer.fromLines(validLines, minLines: 1, maxLines: 5),
          throwsA(
            isA<VocabularyValidationException>().having(
              (e) => e.message,
              'message',
              contains('out of bounds'),
            ),
          ),
        );
      });

      test('fromLines throws VocabularyValidationException on empty or whitespace line', () {
        final badLines = [
          '[PAD]',
          '[UNK]',
          '   ',
          '[CLS]',
          '[SEP]',
        ];
        expect(
          () => WordPieceTokenizer.fromLines(badLines),
          throwsA(
            isA<VocabularyValidationException>().having(
              (e) => e.message,
              'message',
              contains('Vocabulary contains empty or whitespace-only line'),
            ),
          ),
        );
      });

      test('constructor throws VocabularyValidationException when a required special token is missing', () {
        final missingClsVocab = <String, int>{
          '[PAD]': 0,
          '[UNK]': 1,
          '[SEP]': 2,
          'bank': 3,
        };
        expect(
          () => WordPieceTokenizer(missingClsVocab),
          throwsA(
            isA<VocabularyValidationException>().having(
              (e) => e.message,
              'message',
              contains('Missing required special token: [CLS]'),
            ),
          ),
        );
      });

      test('uses resolved instance special token IDs on custom non-standard vocab indices', () {
        final customVocab = <String, int>{
          'first': 0,
          '[SEP]': 1,
          'second': 2,
          '[CLS]': 3,
          'third': 4,
          '[UNK]': 5,
          'bank': 6,
          '[PAD]': 7,
        };

        final customTok = WordPieceTokenizer(customVocab, maxSeqLength: 6);
        expect(customTok.clsId, equals(3));
        expect(customTok.sepId, equals(1));
        expect(customTok.unkId, equals(5));
        expect(customTok.padId, equals(7));

        final ids = customTok.tokenize('bank unknownword');
        // Expected: [CLS](3), bank(6), [UNK](5), [SEP](1), [PAD](7), [PAD](7)
        expect(ids, equals([3, 6, 5, 1, 7, 7]));
      });
    });
  });
}
