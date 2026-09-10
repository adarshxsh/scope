/// WordPiece tokenizer implementation in pure Dart for BERT models.
library;

import 'dart:convert';
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
  final Map<String, int> vocab;
  final int maxSeqLength;

  /// Dynamic verified special token IDs
  final int clsId;
  final int sepId;
  final int padId;
  final int unkId;

  WordPieceTokenizer(
    this.vocab, {
    this.maxSeqLength = 64,
    int minVocabSize = 10,
    int maxVocabSize = 30522,
  })  : clsId = vocab['[CLS]'] ?? -1,
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
    int maxSeqLength = 64,
    String? expectedDigest,
    int minVocabSize = 10,
    int maxVocabSize = 30522,
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
      minVocabSize: minVocabSize,
      maxVocabSize: maxVocabSize,
    );
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
