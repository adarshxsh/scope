import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Custom exception thrown when vocabulary integrity or token contract validation fails.
class VocabularyValidationException implements Exception {
  final String message;
  const VocabularyValidationException(this.message);

  @override
  String toString() => 'VocabularyValidationException: $message';
}

/// Service that verifies cryptographic SHA-256 integrity, line counts,
/// and mandatory special token mappings before tokenizer instantiation.
class VocabValidator {
  /// Pinned SHA-256 digest of assets/vocab.txt
  static const String expectedVocabHash =
      '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

  /// Mandatory BERT special tokens required by the tokenization contract
  static const List<String> mandatorySpecialTokens = [
    '[PAD]',
    '[UNK]',
    '[CLS]',
    '[SEP]',
    '[MASK]',
  ];

  static const int minVocabSize = 1;
  static const int maxVocabSize = 30522;

  /// Computes the SHA-256 hex string digest of raw content.
  static String computeHash(String content) {
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString();
  }

  /// Validates the raw vocabulary text string against expected SHA-256 digest
  /// and line count bounds.
  static void validate(
    String content, {
    String? expectedHash,
    int minLines = minVocabSize,
    int maxLines = maxVocabSize,
  }) {
    final targetHash = expectedHash ?? expectedVocabHash;
    final computedHash = computeHash(content);

    if (computedHash != targetHash) {
      throw VocabularyValidationException(
        'Vocabulary SHA-256 hash mismatch: expected $targetHash, got $computedHash',
      );
    }

    final lines = const LineSplitter().convert(content);
    validateLines(lines, minLines: minLines, maxLines: maxLines);
  }

  /// Validates presence and index bounds of mandatory special tokens.
  static void validateSpecialTokens(
    Map<String, int> vocab, {
    int maxLines = maxVocabSize,
  }) {
    for (final token in mandatorySpecialTokens) {
      final index = vocab[token];
      if (index == null) {
        throw VocabularyValidationException(
          'Missing mandatory special token: $token',
        );
      }
      if (index < 0 || index >= maxLines) {
        throw VocabularyValidationException(
          'Special token $token index $index out of bounds (0..${maxLines - 1})',
        );
      }
    }
  }

  /// Validates line list bounds.
  static void validateLines(
    List<String> lines, {
    int minLines = minVocabSize,
    int maxLines = maxVocabSize,
  }) {
    if (lines.isEmpty || lines.length < minLines || lines.length > maxLines) {
      throw VocabularyValidationException(
        'Vocabulary line count ${lines.length} out of bounds ($minLines..$maxLines)',
      );
    }
  }
}
