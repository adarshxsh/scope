/// WordPiece tokenizer implementation in pure Dart for BERT models.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Exception thrown when vocabulary assets fail validation checks
/// (e.g. SHA-256 mismatch, size limits, missing required special tokens, formatting issues).
class VocabularyValidationException implements Exception {
  final String message;
  VocabularyValidationException(this.message);

  @override
  String toString() => 'VocabularyValidationException: $message';
}

/// Expected ground-truth SHA-256 digest for assets/vocab.txt
const String kDefaultVocabSha256 =
    '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

const String kPadToken = '[PAD]';
const String kUnkToken = '[UNK]';
const String kClsToken = '[CLS]';
const String kSepToken = '[SEP]';
const String kMaskToken = '[MASK]';

const int kMinVocabSize = 4;
const int kMaxVocabSize = 50000;

class WordPieceTokenizer {
  final Map<String, int> vocab;
  final int maxSeqLength;

  late final int padId;
  late final int unkId;
  late final int clsId;
  late final int sepId;
  late final int maskId;

  WordPieceTokenizer(
    this.vocab, {
    this.maxSeqLength = 64,
    bool validate = true,
  }) {
    if (validate) {
      _validateVocab(vocab);
    }
    padId = vocab[kPadToken] ?? _throwMissing(kPadToken);
    unkId = vocab[kUnkToken] ?? _throwMissing(kUnkToken);
    clsId = vocab[kClsToken] ?? _throwMissing(kClsToken);
    sepId = vocab[kSepToken] ?? _throwMissing(kSepToken);
    maskId = vocab[kMaskToken] ?? -1;
  }

  static Never _throwMissing(String token) {
    throw VocabularyValidationException('Missing required special token: $token');
  }

  static void _validateVocab(Map<String, int> vocab) {
    if (vocab.length < kMinVocabSize) {
      throw VocabularyValidationException(
          'Vocabulary size ${vocab.length} is below minimum allowed size $kMinVocabSize.');
    }
    if (vocab.length > kMaxVocabSize) {
      throw VocabularyValidationException(
          'Vocabulary size ${vocab.length} exceeds maximum allowed size $kMaxVocabSize.');
    }
    final requiredTokens = [kPadToken, kUnkToken, kClsToken, kSepToken];
    for (final token in requiredTokens) {
      if (!vocab.containsKey(token)) {
        throw VocabularyValidationException('Missing required special token: $token');
      }
    }
  }

  /// Loads vocabulary from raw string content (e.g. read from assets/vocab.txt).
  factory WordPieceTokenizer.fromContent(
    String content, {
    int maxSeqLength = 64,
    String? expectedChecksum,
    bool validate = true,
  }) {
    if (expectedChecksum != null) {
      final bytes = utf8.encode(content);
      final actualDigest = sha256.convert(bytes).toString();
      if (actualDigest.toLowerCase() != expectedChecksum.toLowerCase()) {
        throw VocabularyValidationException(
            'Vocabulary SHA-256 digest mismatch. Expected: $expectedChecksum, got: $actualDigest');
      }
    }
    final rawLines = content.split('\n');
    return WordPieceTokenizer.fromLines(
      rawLines,
      maxSeqLength: maxSeqLength,
      validate: validate,
    );
  }

  /// Loads vocabulary from a list of lines.
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = 64,
    String? expectedChecksum,
    bool validate = true,
  }) {
    if (expectedChecksum != null) {
      final joined = lines.join('\n');
      final bytes = utf8.encode(joined);
      final actualDigest = sha256.convert(bytes).toString();
      if (actualDigest.toLowerCase() != expectedChecksum.toLowerCase()) {
        throw VocabularyValidationException(
            'Vocabulary SHA-256 digest mismatch. Expected: $expectedChecksum, got: $actualDigest');
      }
    }

    final vocabMap = <String, int>{};
    bool encounteredBlank = false;
    int indexCounter = 0;

    for (int i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        encounteredBlank = true;
        continue;
      }

      if (encounteredBlank && validate) {
        throw VocabularyValidationException(
            'Invalid vocabulary formatting: blank line encountered before line ${i + 1}');
      }

      if (!vocabMap.containsKey(trimmed)) {
        vocabMap[trimmed] = indexCounter;
      }
      indexCounter++;
    }

    return WordPieceTokenizer(
      vocabMap,
      maxSeqLength: maxSeqLength,
      validate: validate,
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
      return [kUnkToken];
    }
    return subwords;
  }
}
