import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';

void main() {
  group('WordPieceTokenizer', () {
    final Map<String, int> vocab = {
      '[PAD]': 0,
      '[UNK]': 1,
      '[CLS]': 2,
      '[SEP]': 3,
      '[MASK]': 10,
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

  group('WordPieceTokenizer Contract & Validation Guardrails', () {
    final validLines = [
      '[PAD]',
      '[UNK]',
      '[CLS]',
      '[SEP]',
      '[MASK]',
      'alert',
      'bank',
      'debited',
      'spent',
      'mom',
      'dad',
      'urgent',
      'sale',
      'promo',
      'discount',
      'msg',
      'email',
      'social',
      'promo',
      'finance',
      'health',
      'news',
      'sys',
      'scholarship',
      '',
    ];

    test('fromLines verifies SHA-256 digest and rejects mismatched digests', () {
      expect(
        () => WordPieceTokenizer.fromLines(
          validLines,
          expectedDigest: '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('fromLines accepts matching SHA-256 digest', () {
      final tokenizer = WordPieceTokenizer.fromLines(
        validLines,
        expectedDigest: WordPieceTokenizer.defaultExpectedDigest,
      );
      expect(tokenizer.vocab['[PAD]'], equals(0));
      expect(tokenizer.vocab['scholarship'], equals(23));
    });

    test('rejects empty lines in the middle to enforce line index continuity', () {
      final linesWithHole = [
        '[PAD]',
        '[UNK]',
        '',
        '[CLS]',
        '[SEP]',
        '[MASK]',
      ];
      expect(
        () => WordPieceTokenizer.fromLines(linesWithHole, expectedDigest: null),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('rejects vocabulary missing mandatory special tokens', () {
      final missingClsLines = [
        '[PAD]',
        '[UNK]',
        '[SEP]',
        '[MASK]',
        'test',
      ];
      expect(
        () => WordPieceTokenizer.fromLines(missingClsLines, expectedDigest: null),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('rejects empty vocabulary', () {
      expect(
        () => WordPieceTokenizer.fromLines([], expectedDigest: null),
        throwsA(isA<VocabularyValidationException>()),
      );
    });
  });
}
