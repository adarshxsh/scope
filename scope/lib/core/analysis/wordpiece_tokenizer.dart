import 'dart:convert';
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
  final Map<String, int> vocab;
  final int maxSeqLength;

  late final int _padId;
  late final int _unkId;
  late final int _clsId;
  late final int _sepId;

  WordPieceTokenizer(
    this.vocab, {
    this.maxSeqLength = 64,
  }) {
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
    int maxSeqLength = 64,
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

    return WordPieceTokenizer(vocabMap, maxSeqLength: maxSeqLength);
  }

  /// Tokenizes the input [text] into a list of vocabulary token IDs.
  /// Automatically adds [CLS] at the start, [SEP] at the end, and pads with [PAD].
  List<int> tokenize(String text) {
    final tokens = _basicTokenize(text);
    final List<int> ids = [];

    ids.add(_clsId);

    for (final token in tokens) {
      if (ids.length >= maxSeqLength - 1) break;

      final subwords = _wordpieceTokenize(token);
      for (final subword in subwords) {
        if (ids.length >= maxSeqLength - 1) break;
        final tokenId = vocab[subword];
        if (tokenId != null && tokenId >= 0 && tokenId < vocab.length) {
          ids.add(tokenId);
        } else {
          ids.add(_unkId);
        }
      }
    }

    // Add [SEP] if there is space, otherwise overwrite the last element
    if (ids.length < maxSeqLength) {
      ids.add(_sepId);
    } else {
      ids[maxSeqLength - 1] = _sepId;
    }

    // Pad with [PAD] IDs
    while (ids.length < maxSeqLength) {
      ids.add(_padId);
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

  List<String> _basicTokenize(String text) {
    final normalized = text.toLowerCase();
    // Match word characters (alphanumeric) or punctuation symbols separately
    final regex = RegExp(r"[a-zA-Z0-9]+|[^\s\w]");
    return regex.allMatches(normalized).map((m) => m.group(0)!).toList();
  }

  List<String> _wordpieceTokenize(String word) {
    final List<String> subwords = [];
    int start = 0;
    bool isBad = false;

    while (start < word.length) {
      int end = word.length;
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
        end--;
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
