import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/models/model_manager.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;

  LiteRtClassifier() {
    initialize();
  }

  /// Reloads category classification model and vocabulary from ModelManager.
  Future<void> reload({File? customModelFile, String? customVocabStr}) async {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _isModelLoaded = false;
    await initialize(customModelFile: customModelFile, customVocabStr: customVocabStr);
  }

  /// Initializes tokenizer and optional category classification model.
  Future<void> initialize({File? customModelFile, String? customVocabStr}) async {
    try {
      // 1. Load Vocabulary (dynamic update or static asset)
      final vocabStr = customVocabStr ?? await ModelManager.instance.getVocabContent();
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(lines);

      // 2. Load Category Model if available
      File? categoryFile = customModelFile ?? await ModelManager.instance.getCategoryModelFile();
      if (categoryFile != null) {
        try {
          final interpreter = Interpreter.fromFile(categoryFile);
          final inputShape = interpreter.getInputTensor(0).shape;
          final outputShape = interpreter.getOutputTensor(0).shape;

          if (inputShape.isNotEmpty && inputShape.last == 64 && outputShape.last == 5) {
            _interpreter = interpreter;
            _isModelLoaded = true;
            debugPrint('LiteRtClassifier: Dynamic category model loaded successfully.');
          } else {
            debugPrint('LiteRtClassifier: Dynamic category model shape mismatch (input: $inputShape, output: $outputShape).');
            interpreter.close();
            _isModelLoaded = false;
          }
        } catch (e) {
          debugPrint('LiteRtClassifier: Exception loading dynamic category model: $e');
          _isModelLoaded = false;
        }
      } else {
        _isModelLoaded = false;
      }
    } catch (e) {
      debugPrint('LiteRtClassifier failed to initialize: $e');
      _isModelLoaded = false;

      // Ensure tokenizer is loaded even if interpreter fails
      if (_tokenizer == null) {
        try {
          final vocabStr = await rootBundle.loadString('assets/vocab.txt');
          _tokenizer = WordPieceTokenizer.fromLines(vocabStr.split('\n'));
        } catch (_) {}
      }
    }
  }

  /// Expose model loading status for diagnostics screen.
  bool get isModelLoaded => _isModelLoaded;

  @override
  Future<AnalysisResult> analyze(AppNotification notification) async {
    final stopwatch = Stopwatch()..start();
    final combinedText = '${notification.title} ${notification.content}';

    // Ensure initialization finished
    if (_tokenizer == null) {
      await initialize();
    }

    final tokenIds = _tokenizer?.tokenize(combinedText) ?? List<int>.filled(64, 0);

    if (!_isModelLoaded || _interpreter == null) {
      // Graceful fallback heuristic classifier
      final category = _runFallbackHeuristic(combinedText);
      return AnalysisResult(
        category: category,
        score: 0.50, // Base default score for fallback
        engineName: 'litert_model (fallback)',
        matchedSignals: [
          'Model asset invalid or uninitialized',
          'Tokenizer parsed ${tokenIds.take(5).toList()}...'
        ],
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    try {
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
