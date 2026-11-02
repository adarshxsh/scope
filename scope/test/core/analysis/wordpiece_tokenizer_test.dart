import 'dart:convert';
import 'package:crypto/crypto.dart';
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

    test('offloads tokenization to background isolate using tokenizeAsync and tokenizeIsolate', () async {
      final idsAsync = await tokenizer.tokenizeAsync('bank alert');
      expect(idsAsync, equals([2, 4, 6, 3, 0, 0, 0, 0]));

      final idsIsolate = await tokenizer.tokenizeIsolate('banking');
      expect(idsIsolate, equals([2, 4, 5, 3, 0, 0, 0, 0]));
    });

    test('preserves multi-byte UTF-16 surrogate pairs and emojis without split surrogates', () {
      final Map<String, int> emojiVocab = {
        '[PAD]': 0,
        '[UNK]': 1,
        '[CLS]': 2,
        '[SEP]': 3,
        'bank': 4,
        'alert': 5,
        '🔥': 6,
        'café': 7,
      };
      final emojiTokenizer = WordPieceTokenizer(emojiVocab, maxSeqLength: 8);

      // Known emoji in vocab
      final idsKnown = emojiTokenizer.tokenize('bank 🔥 alert');
      expect(idsKnown, equals([2, 4, 6, 5, 3, 0, 0, 0]));

      // Unknown emoji (😊) maps to [UNK] (1) cleanly without lone surrogate artifacts
      final idsUnknown = emojiTokenizer.tokenize('bank 😊 alert');
      expect(idsUnknown, equals([2, 4, 1, 5, 3, 0, 0, 0]));

      // Non-ASCII script (Devanagari, accented Latin)
      final idsCafe = emojiTokenizer.tokenize('café alert');
      expect(idsCafe, equals([2, 7, 5, 3, 0, 0, 0, 0]));
    });

    test('caps subword search length on lengthy continuous payloads to avoid quadratic spikes', () {
      // 500 repeated characters should not cause execution freezes
      final lengthyWord = 'x' * 500;
      final stopwatch = Stopwatch()..start();
      final ids = tokenizer.tokenize(lengthyWord);
      stopwatch.stop();

      // Should map the long continuous string to [UNK] quickly
      expect(ids, equals([2, 1, 3, 0, 0, 0, 0, 0]));
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('auto-clamps non-positive sequence lengths to safe minimum bounds', () {
      // Clamping via constructor
      final zeroTokenizer = WordPieceTokenizer(vocab, maxSeqLength: 0);
      expect(zeroTokenizer.maxSeqLength, equals(1));
      final zeroIds = zeroTokenizer.tokenize('bank alert');
      expect(zeroIds.length, equals(1));
      expect(zeroIds[0], equals(2)); // [CLS]

      final negTokenizer = WordPieceTokenizer(vocab, maxSeqLength: -10);
      expect(negTokenizer.maxSeqLength, equals(1));
      final negIds = negTokenizer.tokenize('bank alert');
      expect(negIds.length, equals(1));
      expect(negIds[0], equals(2)); // [CLS]

      // Clamping via tokenize method argument
      final clampedIdsZero = tokenizer.tokenize('bank alert', maxSeqLength: 0);
      expect(clampedIdsZero.length, equals(1));
      expect(clampedIdsZero[0], equals(2));

      final clampedIdsNeg = tokenizer.tokenize('bank alert', maxSeqLength: -5);
      expect(clampedIdsNeg.length, equals(1));
      expect(clampedIdsNeg[0], equals(2));
    });

    test('enforces strict output tensor dimensions across various lengths', () {
      for (final len in [1, 2, 4, 16, 64]) {
        final ids = tokenizer.tokenize('bank alert', maxSeqLength: len);
        expect(ids.length, equals(len));
        expect(ids[0], equals(2)); // [CLS]
        if (len > 1) {
          expect(ids.contains(3), isTrue); // [SEP] present
        }
      }
    });

    group('SHA-256 Checksum Verification', () {
      test('succeeds when vocabulary SHA-256 matches expected digest', () {
        final lines = ['[PAD]', '[UNK]', '[CLS]', '[SEP]', 'a', 'b', 'c', 'd', 'e', 'f'];
        final digest = sha256.convert(utf8.encode(lines.join('\n'))).toString();

        final tok = WordPieceTokenizer.fromLines(lines, expectedDigest: digest);
        expect(tok.vocab.length, equals(10));
      });

      test('throws VocabularyContractException when SHA-256 digest mismatches', () {
        final lines = ['[PAD]', '[UNK]', '[CLS]', '[SEP]', 'a', 'b', 'c', 'd', 'e', 'f'];
        const wrongDigest = '0000000000000000000000000000000000000000000000000000000000000000';

        expect(
          () => WordPieceTokenizer.fromLines(lines, expectedDigest: wrongDigest),
          throwsA(isA<VocabularyContractException>().having(
            (e) => e.message,
            'message',
            contains('Vocabulary SHA-256 digest mismatch'),
          )),
        );
      });
    });

    group('Special Token Contract Validation', () {
      test('throws VocabularyContractException when [CLS] token is omitted', () {
        final invalidVocab = {
          '[PAD]': 0,
          '[UNK]': 1,
          '[SEP]': 2,
          'bank': 3,
          'alert': 4,
          'debit': 5,
          'urgent': 6,
          'a': 7,
          'b': 8,
          'c': 9,
        };
        expect(
          () => WordPieceTokenizer(invalidVocab),
          throwsA(isA<VocabularyContractException>().having(
            (e) => e.message,
            'message',
            contains('Missing mandatory special token(s): [CLS]'),
          )),
        );
      });

      test('throws VocabularyContractException when [SEP] token is omitted', () {
        final invalidVocab = {
          '[PAD]': 0,
          '[UNK]': 1,
          '[CLS]': 2,
          'bank': 3,
          'alert': 4,
          'debit': 5,
          'urgent': 6,
          'a': 7,
          'b': 8,
          'c': 9,
        };
        expect(
          () => WordPieceTokenizer(invalidVocab),
          throwsA(isA<VocabularyContractException>().having(
            (e) => e.message,
            'message',
            contains('Missing mandatory special token(s): [SEP]'),
          )),
        );
      });

      test('throws VocabularyContractException when [PAD] token is omitted', () {
        final invalidVocab = {
          '[UNK]': 0,
          '[CLS]': 1,
          '[SEP]': 2,
          'bank': 3,
          'alert': 4,
          'debit': 5,
          'urgent': 6,
          'a': 7,
          'b': 8,
          'c': 9,
        };
        expect(
          () => WordPieceTokenizer(invalidVocab),
          throwsA(isA<VocabularyContractException>().having(
            (e) => e.message,
            'message',
            contains('Missing mandatory special token(s): [PAD]'),
          )),
        );
      });

      test('throws VocabularyContractException when [UNK] token is omitted', () {
        final invalidVocab = {
          '[PAD]': 0,
          '[CLS]': 1,
          '[SEP]': 2,
          'bank': 3,
          'alert': 4,
          'debit': 5,
          'urgent': 6,
          'a': 7,
          'b': 8,
          'c': 9,
        };
        expect(
          () => WordPieceTokenizer(invalidVocab),
          throwsA(isA<VocabularyContractException>().having(
            (e) => e.message,
            'message',
            contains('Missing mandatory special token(s): [UNK]'),
          )),
        );
      });
    });

    group('Vocabulary Size Bounds Validation', () {
      test('throws VocabularyContractException when vocabulary size is below minVocabSize', () {
        final smallVocab = {
          '[PAD]': 0,
          '[UNK]': 1,
          '[CLS]': 2,
          '[SEP]': 3,
          'word': 4,
        };
        expect(
          () => WordPieceTokenizer(smallVocab, minVocabSize: 10),
          throwsA(isA<VocabularyContractException>().having(
            (e) => e.message,
            'message',
            contains('out of bounds'),
          )),
        );
      });

      test('throws VocabularyContractException when vocabulary size exceeds maxVocabSize', () {
        final lines = List.generate(20, (i) => i < 4 ? ['[PAD]', '[UNK]', '[CLS]', '[SEP]'][i] : 'word$i');
        expect(
          () => WordPieceTokenizer.fromLines(lines, maxVocabSize: 15),
          throwsA(isA<VocabularyContractException>().having(
            (e) => e.message,
            'message',
            contains('out of bounds'),
          )),
        );
      });
    });

    group('Dynamic Special Token Lookup', () {
      test('uses dynamic indices for CLS, SEP, PAD, UNK instead of hardcoded BERT fallbacks', () {
        final nonStandardVocab = {
          'word1': 0,
          'word2': 1,
          '[PAD]': 10,
          '[UNK]': 20,
          '[CLS]': 30,
          '[SEP]': 40,
          'bank': 50,
          'alert': 60,
          'a': 70,
          'b': 80,
        };

        final tok = WordPieceTokenizer(nonStandardVocab, maxSeqLength: 8);
        expect(tok.clsId, equals(30));
        expect(tok.sepId, equals(40));
        expect(tok.padId, equals(10));
        expect(tok.unkId, equals(20));

        final ids = tok.tokenize('bank unknown');
        // Expected: [CLS](30), bank(50), [UNK](20), [SEP](40), [PAD](10), [PAD](10), [PAD](10), [PAD](10)
        expect(ids, equals([30, 50, 20, 40, 10, 10, 10, 10]));
      });
    });
  });
}
