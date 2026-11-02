/// WordPiece tokenizer implementation in pure Dart for BERT models.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

/// Exception thrown when vocabulary assets or structure fail validation checks.
class VocabularyValidationException implements Exception {
  final String message;
  VocabularyValidationException(this.message);

  @override
  String toString() => 'VocabularyValidationException: $message';
}

class WordPieceTokenizer {
  static const int minSeqLength = 1;
  static const int defaultMaxSeqLength = 64;
  static const int defaultMaxInputCharsPerWord = 100;
  static const String defaultVocabSha256 =
      '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

  final Map<String, int> vocab;
  final int maxSeqLength;
  final int maxInputCharsPerWord;
  final int padId;
  final int unkId;
  final int clsId;
  final int sepId;

  WordPieceTokenizer(
    this.vocab, {
    int maxSeqLength = defaultMaxSeqLength,
    this.maxInputCharsPerWord = defaultMaxInputCharsPerWord,
  })  : maxSeqLength = maxSeqLength < minSeqLength ? minSeqLength : maxSeqLength,
        padId = _getRequiredToken(vocab, '[PAD]'),
        unkId = _getRequiredToken(vocab, '[UNK]'),
        clsId = _getRequiredToken(vocab, '[CLS]'),
        sepId = _getRequiredToken(vocab, '[SEP]') {
    _validateVocab();
  }

  static int _getRequiredToken(Map<String, int> vocab, String token) {
    final id = vocab[token];
    if (id == null) {
      throw VocabularyValidationException(
        'Missing required special token: $token',
      );
    }
    return id;
  }

  void _validateVocab() {
    if (vocab.isEmpty) {
      throw VocabularyValidationException('Vocabulary map cannot be empty');
    }
    for (final entry in vocab.entries) {
      if (entry.key.trim().isEmpty) {
        throw VocabularyValidationException(
          'Vocabulary contains empty or whitespace-only token key',
        );
      }
      if (entry.value < 0) {
        throw VocabularyValidationException(
          'Vocabulary token ID for "${entry.key}" is negative: ${entry.value}',
        );
      }
    }
  }

  /// Loads vocabulary from a list of lines (e.g. from vocab.txt).
  /// Performs SHA-256 validation (if [expectedHash] provided), line count bounds checking,
  /// empty line validation, and required special token resolution.
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = defaultMaxSeqLength,
    int maxInputCharsPerWord = defaultMaxInputCharsPerWord,
    String? expectedHash,
    int minLines = 4,
    int? maxLines,
  }) {
    // 1. Verify SHA-256 hash if expectedHash is specified
    if (expectedHash != null) {
      final content = lines.join('\n');
      final bytes = utf8.encode(content);
      final digest = sha256.convert(bytes).toString().toLowerCase();
      if (digest != expectedHash.toLowerCase()) {
        throw VocabularyValidationException(
          'SHA-256 digest mismatch. Expected $expectedHash, got $digest',
        );
      }
    }

    // Normalize: strip single trailing empty string from trailing newline if present
    final effectiveLines = List<String>.from(lines);
    if (effectiveLines.isNotEmpty && effectiveLines.last.isEmpty) {
      effectiveLines.removeLast();
    }

    // 2. Validate line count bounds
    if (effectiveLines.length < minLines ||
        (maxLines != null && effectiveLines.length > maxLines)) {
      throw VocabularyValidationException(
        'Vocabulary line count (${effectiveLines.length}) is out of bounds '
        '[min: $minLines, max: ${maxLines ?? "unlimited"}]',
      );
    }

    // 3. Build vocab map while enforcing non-empty/non-whitespace lines
    final vocabMap = <String, int>{};
    for (int i = 0; i < effectiveLines.length; i++) {
      final rawLine = effectiveLines[i];
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) {
        throw VocabularyValidationException(
          'Vocabulary contains empty or whitespace-only line at line ${i + 1}',
        );
      }
      vocabMap[trimmed] = i;
    }

    return WordPieceTokenizer(
      vocabMap,
      maxSeqLength: maxSeqLength,
      maxInputCharsPerWord: maxInputCharsPerWord,
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
        final subwordId = vocab[subword] ?? unkId;
        if (subwordId < 0) {
          ids.add(unkId);
        } else {
          ids.add(subwordId);
        }
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
