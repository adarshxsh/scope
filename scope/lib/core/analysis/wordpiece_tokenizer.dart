/// WordPiece tokenizer implementation in pure Dart for BERT models.
library;

import 'package:scope/core/analysis/vocab_validator.dart';

class WordPieceTokenizer {
  final Map<String, int> vocab;
  final int maxSeqLength;

  WordPieceTokenizer(this.vocab, {this.maxSeqLength = 64}) {
    VocabValidator.validateSpecialTokens(vocab);
  }

  /// Loads vocabulary from a list of lines (e.g. from vocab.txt).
  factory WordPieceTokenizer.fromLines(
    List<String> lines, {
    int maxSeqLength = 64,
  }) {
    VocabValidator.validateLines(lines);
    final vocabMap = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        vocabMap[line] = i;
      }
    }
    VocabValidator.validateSpecialTokens(vocabMap);
    return WordPieceTokenizer(vocabMap, maxSeqLength: maxSeqLength);
  }

  /// Tokenizes the input [text] into a list of vocabulary token IDs.
  /// Automatically adds [CLS] at the start, [SEP] at the end, and pads with [PAD].
  List<int> tokenize(String text) {
    final tokens = _basicTokenize(text);
    final List<int> ids = [];

    final clsId = vocab['[CLS]'];
    final sepId = vocab['[SEP]'];
    final padId = vocab['[PAD]'];
    final unkId = vocab['[UNK]'];

    if (clsId == null || sepId == null || padId == null || unkId == null) {
      throw const VocabularyValidationException(
        'Mandatory special token missing from vocabulary',
      );
    }

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
