import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;
  String? _vocabValidationError;

  static const String expectedVocabSha256 =
      WordPieceTokenizer.defaultVocabSha256;

  LiteRtClassifier() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _vocabValidationError = null;
      // 1. Load Vocab
      final vocabStr = await rootBundle.loadString('assets/vocab.txt');
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(
        lines,
        expectedHash: expectedVocabSha256,
      );

      // 2. Load Interpreter (Bypassed: model.tflite is now the look-again regression model)
      _isModelLoaded = false;
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      // ignore: avoid_print
      print('LiteRtClassifier failed to initialize: $e');
      _isModelLoaded = false;
      _tokenizer = null;
      _vocabValidationError = e.toString();
    }
  }

  /// Expose model loading status for diagnostics screen.
  bool get isModelLoaded => _isModelLoaded;

  @override
  Future<AnalysisResult> analyze(AppNotification notification) async {
    final stopwatch = Stopwatch()..start();
    final combinedText = '${notification.title} ${notification.content}';

    // Ensure initialization finished
    if (_tokenizer == null && _vocabValidationError == null) {
      await _initialize();
    }

    if (_tokenizer == null || !_isModelLoaded || _interpreter == null) {
      // Graceful fallback heuristic classifier
      final category = _runFallbackHeuristic(combinedText);
      final matchedSignals = <String>[];
      if (_vocabValidationError != null) {
        matchedSignals.add('Vocabulary validation failed: $_vocabValidationError');
      } else {
        matchedSignals.add('Model asset invalid or uninitialized');
      }

      if (_tokenizer != null) {
        final tokenIds = _tokenizer!.tokenize(combinedText);
        matchedSignals.add('Tokenizer parsed ${tokenIds.take(5).toList()}...');
      } else {
        matchedSignals.add('Tokenizer unavailable due to validation failure');
      }

      return AnalysisResult(
        category: category,
        score: 0.50, // Base default score for fallback
        engineName: 'litert_model (fallback)',
        matchedSignals: matchedSignals,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    try {
      final tokenIds = _tokenizer!.tokenize(combinedText);

      // Run model inference
      // Assume input shape: [1, 64]
      final input = [tokenIds];
      
      // Output logit tensor shape: [1, 5] (Promo, Social, System, Message, Finance)
      final output = List<double>.filled(5, 0.0).reshape([1, 5]);

      _interpreter!.run(input, output);

      final scores = List<double>.from(output[0] as List);
      final softmaxScores = _softmax(scores);

      int bestIndex = 0;
      double maxScore = -1.0;
      for (int i = 0; i < softmaxScores.length; i++) {
        if (softmaxScores[i] > maxScore) {
          maxScore = softmaxScores[i];
          bestIndex = i;
        }
      }

      final categories = ['promo', 'social', 'sys', 'msg', 'finance'];
      final predictedCategory = categories[bestIndex];

      return AnalysisResult(
        category: predictedCategory,
        score: maxScore,
        engineName: 'litert_model',
        matchedSignals: ['Softmax scores: $softmaxScores'],
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      // Fallback on inference error
      final category = _runFallbackHeuristic(combinedText);
      return AnalysisResult(
        category: category,
        score: 0.50,
        engineName: 'litert_model (fallback on error)',
        matchedSignals: ['Inference error: $e'],
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  String _runFallbackHeuristic(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('otp') || lower.contains('verification') || lower.contains('code')) {
      return 'sys';
    }
    if (lower.contains('debited') || lower.contains('spent') || lower.contains('withdraw') || lower.contains('rs.') || lower.contains('inr')) {
      return 'finance';
    }
    if (lower.contains('appointment') || lower.contains('doctor') || lower.contains('medicine')) {
      return 'health';
    }
    if (lower.contains('sale') || lower.contains('discount') || lower.contains('promo') || lower.contains('off')) {
      return 'promo';
    }
    if (lower.contains('liked') || lower.contains('followed') || lower.contains('commented')) {
      return 'social';
    }
    if (lower.contains('deadline') || lower.contains('scholarship')) {
      return 'scholarship';
    }
    return 'msg'; // default fallback semantic category
  }

  List<double> _softmax(List<double> logits) {
    double max = logits.reduce((curr, next) => curr > next ? curr : next);
    List<double> exps = logits.map((x) => math.exp(x - max)).toList();
    final sum = exps.reduce((curr, next) => curr + next);
    if (sum == 0.0) return List<double>.filled(logits.length, 1.0 / logits.length);
    return exps.map((x) => x / sum).toList();
  }
}
