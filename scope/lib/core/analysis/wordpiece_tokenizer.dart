import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

/// Exception thrown when vocabulary validation or cryptographic checksum verification fails.
class VocabularyValidationException implements Exception {
  final String message;
  VocabularyValidationException(this.message);

  @override
  String toString() => 'VocabularyValidationException: $message';
}

/// WordPiece tokenizer implementation in pure Dart for BERT models.
class WordPieceTokenizer {
  static const int minSeqLength = 1;
  static const int defaultMaxSeqLength = 64;
  static const int defaultMaxInputCharsPerWord = 100;

  final Map<String, int> vocab;
  final int maxSeqLength;
  final int maxInputCharsPerWord;

  late final int _padId;
  late final int _unkId;
  late final int _clsId;
  late final int _sepId;

  WordPieceTokenizer(
    this.vocab, {
    int maxSeqLength = defaultMaxSeqLength,
    this.maxInputCharsPerWord = defaultMaxInputCharsPerWord,
  }) : maxSeqLength = maxSeqLength < minSeqLength ? minSeqLength : maxSeqLength {
    _validateAndInitSpecialTokens();
  }

  void _validateAndInitSpecialTokens() {
    if (vocab.isEmpty) {
      throw VocabularyValidationException('Vocabulary map cannot be empty.');
    }

    final mandatoryTokens = ['[PAD]', '[UNK]', '[CLS]', '[SEP]'];
    for (final token in mandatoryTokens) {
      if (!vocab.containsKey(token)) {
        throw VocabularyValidationException(
          'Missing mandatory special token "$token" in vocabulary schema.',
        );
      }
      final id = vocab[token]!;
      if (id < 0 || id >= vocab.length) {
        throw VocabularyValidationException(
          'Special token "$token" ID $id is out of vocabulary bounds (0..${vocab.length - 1}).',
        );
      }
    }

    _padId = vocab['[PAD]']!;
    _unkId = vocab['[UNK]']!;
    _clsId = vocab['[CLS]']!;
    _sepId = vocab['[SEP]']!;
  }

  /// Loads vocabulary from a list of lines (e.g. from vocab.txt).
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = defaultMaxSeqLength,
    int maxInputCharsPerWord = defaultMaxInputCharsPerWord,
    String? expectedSha256,
  }) {
    if (lines.isEmpty) {
      throw VocabularyValidationException('Vocabulary asset is empty.');
    }

    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final rawContent = lines.join('\n');
      final digest = sha256.convert(utf8.encode(rawContent)).toString();
      if (digest.toLowerCase() != expectedSha256.toLowerCase()) {
        throw VocabularyValidationException(
          'Vocabulary SHA-256 digest mismatch. Expected $expectedSha256, got $digest',
        );
      }
    }

    // Strip trailing empty lines (common when splitting text ending with \n)
    int endIndex = lines.length;
    while (endIndex > 0 && lines[endIndex - 1].trim().isEmpty) {
      endIndex--;
    }

    if (endIndex == 0) {
      throw VocabularyValidationException('Vocabulary asset contains only empty lines.');
    }

    final vocabMap = <String, int>{};
    for (int i = 0; i < endIndex; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        throw VocabularyValidationException(
          'Empty line detected at index $i, desynchronizing token IDs from line positions.',
        );
      }
      vocabMap.putIfAbsent(line, () => i);
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

    ids.add(_clsId);

    for (final token in tokens) {
      if (ids.length >= targetLength - 1) break;

      final subwords = _wordpieceTokenize(token);
      for (final subword in subwords) {
        if (ids.length >= targetLength - 1) break;
        final tokenId = vocab[subword];
        if (tokenId != null && tokenId >= 0 && tokenId < vocab.length) {
          ids.add(tokenId);
        } else {
          ids.add(_unkId);
        }
      }
    }

    // Add [SEP] if there is space, otherwise overwrite the last element
    if (ids.length < targetLength) {
      ids.add(_sepId);
    } else if (targetLength > 1) {
      ids[targetLength - 1] = _sepId;
    }

    // Pad with [PAD] IDs
    while (ids.length < targetLength) {
      ids.add(_padId);
    }

    // Strict boundary enforcement: guarantee output vector matches targetLength
    if (ids.length > targetLength) {
      ids.length = targetLength;
    }

    // Verify all generated token IDs are within 0 <= id < vocab.length
    for (int i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (id < 0 || id >= vocab.length) {
        throw VocabularyValidationException(
          'Generated token ID $id at position $i is out of vocabulary bounds (0..${vocab.length - 1}).',
        );
      }
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
