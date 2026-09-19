import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Exception thrown when vocabulary verification or contract validation fails.
class VocabularyValidationException implements Exception {
  final String message;

  VocabularyValidationException(this.message);

  @override
  String toString() => 'VocabularyValidationException: $message';
}

/// WordPiece tokenizer implementation in pure Dart for BERT models.
class WordPieceTokenizer {
  static const String defaultExpectedDigest =
      '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';
  static const List<String> mandatorySpecialTokens = [
    '[PAD]',
    '[UNK]',
    '[CLS]',
    '[SEP]',
    '[MASK]',
  ];
  static const int maxVocabSize = 50000;

  final Map<String, int> vocab;
  final int maxSeqLength;

  final int padId;
  final int unkId;
  final int clsId;
  final int sepId;
  final int maskId;

  WordPieceTokenizer(this.vocab, {this.maxSeqLength = 64})
      : padId = _extractSpecialToken(vocab, '[PAD]'),
        unkId = _extractSpecialToken(vocab, '[UNK]'),
        clsId = _extractSpecialToken(vocab, '[CLS]'),
        sepId = _extractSpecialToken(vocab, '[SEP]'),
        maskId = _extractSpecialToken(vocab, '[MASK]') {
    if (vocab.isEmpty) {
      throw VocabularyValidationException('Vocabulary map cannot be empty');
    }
    if (vocab.length > maxVocabSize) {
      throw VocabularyValidationException(
          'Vocabulary size ${vocab.length} exceeds maximum limit of $maxVocabSize');
    }
  }

  static int _extractSpecialToken(Map<String, int> vocab, String token) {
    final id = vocab[token];
    if (id == null) {
      throw VocabularyValidationException(
          'Missing mandatory special token: $token');
    }
    return id;
  }

  /// Loads and validates vocabulary from a list of lines (e.g. from vocab.txt).
  /// Verifies SHA-256 digest, line count bounds, line index continuity, and special tokens.
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = 64,
    String? expectedDigest = defaultExpectedDigest,
  }) {
    if (lines.isEmpty) {
      throw VocabularyValidationException('Vocabulary line count must be non-zero');
    }

    // 1. Verify cryptographic SHA-256 digest if expectedDigest is provided
    if (expectedDigest != null && expectedDigest.isNotEmpty) {
      final rawText = lines.join('\n');
      final actualDigest = sha256.convert(utf8.encode(rawText)).toString();
      if (actualDigest.toLowerCase() != expectedDigest.toLowerCase()) {
        throw VocabularyValidationException(
            'SHA-256 digest mismatch: expected $expectedDigest, got $actualDigest');
      }
    }

    // Trim trailing empty lines resulting from a trailing newline at EOF
    final processedLines = List<String>.from(lines);
    while (processedLines.isNotEmpty && processedLines.last.trim().isEmpty) {
      processedLines.removeLast();
    }

    if (processedLines.isEmpty) {
      throw VocabularyValidationException('Vocabulary line count must be non-zero');
    }

    if (processedLines.length > maxVocabSize) {
      throw VocabularyValidationException(
          'Vocabulary line count (${processedLines.length}) exceeds maximum limit ($maxVocabSize)');
    }

    // 2. Strict line index continuity check
    final vocabMap = <String, int>{};
    for (int i = 0; i < processedLines.length; i++) {
      final line = processedLines[i].trim();
      if (line.isEmpty) {
        throw VocabularyValidationException(
            'Empty line at index $i violates line index continuity');
      }
      vocabMap[line] = i;
    }

    return WordPieceTokenizer(vocabMap, maxSeqLength: maxSeqLength);
  }

  /// Tokenizes the input [text] into a list of vocabulary token IDs.
  /// Automatically adds [CLS] at the start, [SEP] at the end, and pads with [PAD].
  List<int> tokenize(String text) {
    final tokens = _basicTokenize(text);
    final List<int> ids = [];

    ids.add(clsId);

    for (final token in tokens) {
      if (ids.length >= maxSeqLength - 1) break;

      final subwords = _wordpieceTokenize(token);
      for (final subword in subwords) {
        if (ids.length >= maxSeqLength - 1) break;
        ids.add(vocab[subword] ?? unkId);
      }
    }

    // Add [SEP] if there is space, otherwise overwrite the last element
    if (ids.length < maxSeqLength) {
      ids.add(sepId);
    } else {
      ids[maxSeqLength - 1] = sepId;
    }

    // Pad with [PAD] IDs
    while (ids.length < maxSeqLength) {
      ids.add(padId);
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
