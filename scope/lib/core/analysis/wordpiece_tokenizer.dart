import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Exception thrown when vocabulary validation fails.
class VocabularyValidationException implements Exception {
  final String message;
  VocabularyValidationException(this.message);

  @override
  String toString() => 'VocabularyValidationException: $message';
}

/// Special tokens required in WordPiece vocabulary for BERT models.
class SpecialTokens {
  static const String pad = '[PAD]';
  static const String unk = '[UNK]';
  static const String cls = '[CLS]';
  static const String sep = '[SEP]';

  static const List<String> requiredTokens = [pad, unk, cls, sep];
}

/// WordPiece tokenizer implementation in pure Dart for BERT models.
class WordPieceTokenizer {
  final Map<String, int> vocab;
  final int maxSeqLength;
  final int clsId;
  final int sepId;
  final int padId;
  final int unkId;

  WordPieceTokenizer(
    this.vocab, {
    this.maxSeqLength = 64,
    bool validate = true,
    int maxVocabSize = 50000,
  })  : clsId = vocab[SpecialTokens.cls] ?? 101,
        sepId = vocab[SpecialTokens.sep] ?? 102,
        padId = vocab[SpecialTokens.pad] ?? 0,
        unkId = vocab[SpecialTokens.unk] ?? 100 {
    if (validate) {
      validateVocabulary(vocab, maxVocabSize: maxVocabSize);
    }
  }

  /// Validates a vocabulary map, ensuring required special tokens exist and size limits are respected.
  static void validateVocabulary(
    Map<String, int> vocab, {
    String? content,
    String? expectedSha256,
    int maxVocabSize = 50000,
  }) {
    if (vocab.isEmpty) {
      throw VocabularyValidationException('Vocabulary is empty.');
    }

    if (vocab.length > maxVocabSize) {
      throw VocabularyValidationException(
        'Vocabulary size (${vocab.length}) exceeds maximum allowed limit ($maxVocabSize).',
      );
    }

    for (final token in SpecialTokens.requiredTokens) {
      if (!vocab.containsKey(token)) {
        throw VocabularyValidationException(
          'Missing required special token: "$token".',
        );
      }
    }

    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      if (content == null) {
        throw VocabularyValidationException(
          'Raw content must be provided for SHA-256 digest verification.',
        );
      }
      final computedHash = sha256.convert(utf8.encode(content)).toString();
      if (computedHash.toLowerCase() != expectedSha256.toLowerCase()) {
        throw VocabularyValidationException(
          'SHA-256 digest mismatch. Expected: $expectedSha256, Computed: $computedHash.',
        );
      }
    }
  }

  /// Loads vocabulary from raw string content (e.g. from vocab.txt asset).
  factory WordPieceTokenizer.fromContent(
    String content, {
    int maxSeqLength = 64,
    String? expectedSha256,
    int maxVocabSize = 50000,
    bool validate = true,
  }) {
    final lines = content.split(RegExp(r'\r?\n'));
    final vocabMap = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        vocabMap.putIfAbsent(line, () => i);
      }
    }

    if (validate) {
      validateVocabulary(
        vocabMap,
        content: content,
        expectedSha256: expectedSha256,
        maxVocabSize: maxVocabSize,
      );
    }

    return WordPieceTokenizer(
      vocabMap,
      maxSeqLength: maxSeqLength,
      validate: false,
      maxVocabSize: maxVocabSize,
    );
  }

  /// Loads vocabulary from a list of lines (e.g. from vocab.txt).
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = 64,
    String? expectedSha256,
    int maxVocabSize = 50000,
    bool validate = true,
  }) {
    final vocabMap = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        vocabMap.putIfAbsent(line, () => i);
      }
    }

    final content = lines.join('\n');

    if (validate) {
      validateVocabulary(
        vocabMap,
        content: content,
        expectedSha256: expectedSha256,
        maxVocabSize: maxVocabSize,
      );
    }

    return WordPieceTokenizer(
      vocabMap,
      maxSeqLength: maxSeqLength,
      validate: false,
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
