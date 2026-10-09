/// WordPiece tokenizer implementation in pure Dart for BERT models.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Exception thrown when vocabulary assets or structure fail validation checks.
class VocabularyValidationException implements Exception {
  final String message;
  VocabularyValidationException(this.message);

  @override
  String toString() => 'VocabularyValidationException: $message';
}

class WordPieceTokenizer {
  static const String defaultVocabSha256 =
      '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

  final Map<String, int> vocab;
  final int maxSeqLength;
  final int padId;
  final int unkId;
  final int clsId;
  final int sepId;

  WordPieceTokenizer(this.vocab, {this.maxSeqLength = 64})
      : padId = _getRequiredToken(vocab, '[PAD]'),
        unkId = _getRequiredToken(vocab, '[UNK]'),
        clsId = _getRequiredToken(vocab, '[CLS]'),
        sepId = _getRequiredToken(vocab, '[SEP]');

  static int _getRequiredToken(Map<String, int> vocab, String token) {
    final id = vocab[token];
    if (id == null) {
      throw VocabularyValidationException(
        'Missing required special token: $token',
      );
    }
    return id;
  }

  /// Loads vocabulary from a list of lines (e.g. from vocab.txt).
  /// Performs SHA-256 validation (if [expectedHash] provided), line count bounds checking,
  /// empty line validation, and required special token resolution.
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = 64,
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
