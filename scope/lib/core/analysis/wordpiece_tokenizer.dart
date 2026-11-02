/// WordPiece tokenizer implementation in pure Dart for BERT models.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

/// Exception thrown when vocabulary fails SHA-256 digest verification,
/// size bounds, or special token contract requirements.
class VocabularyContractException implements Exception {
  final String message;
  const VocabularyContractException(this.message);

  @override
  String toString() => 'VocabularyContractException: $message';
}

/// Expected SHA-256 checksum for the standard assets/vocab.txt file.
const String kExpectedVocabSha256 =
    '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

class WordPieceTokenizer {
  static const int minSeqLength = 1;
  static const int defaultMaxSeqLength = 64;
  static const int defaultMaxInputCharsPerWord = 100;
  static const int defaultMinVocabSize = 4;
  static const int defaultMaxVocabSize = 30522;

  final Map<String, int> vocab;
  final int maxSeqLength;
  final int maxInputCharsPerWord;

  /// Dynamic verified special token IDs
  final int clsId;
  final int sepId;
  final int padId;
  final int unkId;

  WordPieceTokenizer(
    this.vocab, {
    int maxSeqLength = defaultMaxSeqLength,
    this.maxInputCharsPerWord = defaultMaxInputCharsPerWord,
    int minVocabSize = defaultMinVocabSize,
    int maxVocabSize = defaultMaxVocabSize,
  })  : maxSeqLength = maxSeqLength < minSeqLength ? minSeqLength : maxSeqLength,
        clsId = vocab['[CLS]'] ?? -1,
        sepId = vocab['[SEP]'] ?? -1,
        padId = vocab['[PAD]'] ?? -1,
        unkId = vocab['[UNK]'] ?? -1 {
    _validateContract(minVocabSize: minVocabSize, maxVocabSize: maxVocabSize);
  }

  void _validateContract({required int minVocabSize, required int maxVocabSize}) {
    if (vocab.length < minVocabSize || vocab.length > maxVocabSize) {
      throw VocabularyContractException(
        'Vocabulary size (${vocab.length}) out of bounds [$minVocabSize, $maxVocabSize]',
      );
    }

    final missingTokens = <String>[];
    if (clsId == -1) missingTokens.add('[CLS]');
    if (sepId == -1) missingTokens.add('[SEP]');
    if (padId == -1) missingTokens.add('[PAD]');
    if (unkId == -1) missingTokens.add('[UNK]');

    if (missingTokens.isNotEmpty) {
      throw VocabularyContractException(
        'Missing mandatory special token(s): ${missingTokens.join(', ')}',
      );
    }
  }

  /// Loads vocabulary from a list of lines (e.g. from vocab.txt).
  ///
  /// Optionally verifies the SHA-256 digest against [expectedDigest]
  /// and validates vocabulary size bounds and required special tokens.
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = defaultMaxSeqLength,
    int maxInputCharsPerWord = defaultMaxInputCharsPerWord,
    String? expectedDigest,
    int minVocabSize = defaultMinVocabSize,
    int maxVocabSize = defaultMaxVocabSize,
  }) {
    if (expectedDigest != null) {
      final content = lines.join('\n');
      final actualDigest = sha256.convert(utf8.encode(content)).toString();
      if (actualDigest.toLowerCase() != expectedDigest.toLowerCase()) {
        throw VocabularyContractException(
          'Vocabulary SHA-256 digest mismatch. Expected: $expectedDigest, Actual: $actualDigest',
        );
      }
    }

    final vocabMap = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        vocabMap.putIfAbsent(line, () => i);
      }
    }

    return WordPieceTokenizer(
      vocabMap,
      maxSeqLength: maxSeqLength,
      maxInputCharsPerWord: maxInputCharsPerWord,
      minVocabSize: minVocabSize,
      maxVocabSize: maxVocabSize,
    );
  }

  /// Tokenizes the input [text] into a list of vocabulary token IDs.
  /// Automatically adds [CLS] at the start, [SEP] at the end, and pads with [PAD].
  List<int> tokenize(String text, {int? maxSeqLength}) {
    final targetLength = math.max(minSeqLength, maxSeqLength ?? this.maxSeqLength);
    final tokens = _basicTokenize(text);
    final List<int> ids = [];

    ids.add(clsId);

    for (final token in tokens) {
      if (ids.length >= targetLength - 1) break;

      final subwords = _wordpieceTokenize(token);
      for (final subword in subwords) {
        if (ids.length >= targetLength - 1) break;
        ids.add(vocab[subword] ?? unkId);
      }
    }

    // Add [SEP] if there is space, otherwise overwrite the last element
    if (ids.length < targetLength) {
      ids.add(sepId);
    } else if (targetLength > 1) {
      ids[targetLength - 1] = sepId;
    }

    // Pad with [PAD] IDs
    while (ids.length < targetLength) {
      ids.add(padId);
    }

    // Strict boundary enforcement: guarantee output vector matches targetLength
    if (ids.length > targetLength) {
      ids.length = targetLength;
    }

    return ids;
  }

  /// Asynchronously tokenizes [text] on a background isolate off the main event loop.
  Future<List<int>> tokenizeAsync(String text, {int? maxSeqLength}) {
    final targetLength = math.max(minSeqLength, maxSeqLength ?? this.maxSeqLength);
    return Isolate.run(() => tokenize(text, maxSeqLength: targetLength));
  }

  /// Alias for [tokenizeAsync] explicitly indicating background isolate execution.
  Future<List<int>> tokenizeIsolate(String text, {int? maxSeqLength}) =>
      tokenizeAsync(text, maxSeqLength: maxSeqLength);

  List<String> _basicTokenize(String text) {
    final normalized = text.toLowerCase();
    // Unicode-aware regex matching word characters (letters, numbers, combining marks)
    // or punctuation / symbols separately while preserving surrogate pairs and emojis
    final regex = RegExp(r"[\p{L}\p{N}\p{M}]+|[^\s\p{L}\p{N}\p{M}]", unicode: true);
    return regex.allMatches(normalized).map((m) => m.group(0)!).toList();
  }

  bool _isSurrogateLead(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
  bool _isSurrogateTrail(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  int _prevCodePointIndex(String str, int index, int minIndex) {
    if (index > minIndex + 1 &&
        _isSurrogateTrail(str.codeUnitAt(index - 1)) &&
        _isSurrogateLead(str.codeUnitAt(index - 2))) {
      return index - 2;
    }
    return index - 1;
  }

  List<String> _wordpieceTokenize(String word) {
    // Fast path: avoid quadratic processing on excessively long continuous strings/payloads
    if (word.length > maxInputCharsPerWord) {
      return ['[UNK]'];
    }

    final List<String> subwords = [];
    int start = 0;
    bool isBad = false;

    while (start < word.length) {
      int end = math.min(word.length, start + maxInputCharsPerWord);
      // Ensure end boundary does not split a surrogate pair
      if (end < word.length &&
          end > start &&
          _isSurrogateTrail(word.codeUnitAt(end)) &&
          _isSurrogateLead(word.codeUnitAt(end - 1))) {
        end--;
      }

      String curSubword = '';
      bool found = false;

      while (start < end) {
        String substr = word.substring(start, end);
        if (start > 0) {
          substr = '##$substr';
        }

        if (vocab.containsKey(substr)) {
          curSubword = substr;
          found = true;
          break;
        }
        end = _prevCodePointIndex(word, end, start);
      }

      if (!found) {
        isBad = true;
        break;
      }

      subwords.add(curSubword);
      start = end;
    }

    if (isBad) {
      return ['[UNK]'];
    }
    return subwords;
  }
}
