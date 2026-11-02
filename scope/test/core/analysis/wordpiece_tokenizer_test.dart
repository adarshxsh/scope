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

    test('throws VocabularyValidationException when mandatory special token is missing', () {
      final invalidVocab = <String, int>{
        '[PAD]': 0,
        '[UNK]': 1,
        '[CLS]': 2,
        // missing [SEP]
      };
      expect(
        () => WordPieceTokenizer(invalidVocab),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('throws VocabularyValidationException when special token ID is out of bounds', () {
      final invalidVocab = <String, int>{
        '[PAD]': 0,
        '[UNK]': 1,
        '[CLS]': 2,
        '[SEP]': 102, // out of bounds since vocab length is 4
      };
      expect(
        () => WordPieceTokenizer(invalidVocab),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('throws VocabularyValidationException when fromLines encounters an empty line within vocabulary', () {
      final lines = ['[PAD]', '[UNK]', '', '[CLS]', '[SEP]'];
      expect(
        () => WordPieceTokenizer.fromLines(lines),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('fromLines verifies SHA-256 digest when expectedSha256 is provided', () {
      final lines = ['[PAD]', '[UNK]', '[CLS]', '[SEP]', 'bank'];
      const correctHash = '83b29afefcbf61d997712734a9c203d4cc988ae51bb5af43a5e4733561e53877';
      
      final tok = WordPieceTokenizer.fromLines(lines, expectedSha256: correctHash);
      expect(tok.vocab.length, equals(5));

      expect(
        () => WordPieceTokenizer.fromLines(lines, expectedSha256: 'invalidsha256hash'),
        throwsA(isA<VocabularyValidationException>()),
      );
    });

    test('uses dynamic special token indices and verifies all token IDs are in bounds 0 <= id < vocab.length', () {
      final dynamicVocab = <String, int>{
        '[SEP]': 0,
        '[CLS]': 1,
        '[UNK]': 2,
        '[PAD]': 3,
        'hello': 4,
      };

      final customTokenizer = WordPieceTokenizer(dynamicVocab, maxSeqLength: 6);
      final ids = customTokenizer.tokenize('hello world');

      expect(ids.length, equals(6));
      expect(ids[0], equals(1)); // [CLS] at index 1
      expect(ids[1], equals(4)); // hello at index 4
      expect(ids[2], equals(2)); // world -> [UNK] at index 2
      expect(ids[3], equals(0)); // [SEP] at index 0
      expect(ids[4], equals(3)); // [PAD] at index 3
      expect(ids[5], equals(3)); // [PAD] at index 3

      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThan(dynamicVocab.length));
      }
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
  });
}
