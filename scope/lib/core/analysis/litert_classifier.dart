import 'dart:math' as math;
import 'package:flutter/foundation.dart';
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
  String _diagnosticMessage = 'Uninitialized';
  final String modelPath;
  final String vocabPath;

  LiteRtClassifier({
    this.modelPath = 'assets/model.tflite',
    this.vocabPath = 'assets/vocab.txt',
    Interpreter? customInterpreter,
  }) {
    if (customInterpreter != null) {
      _interpreter = customInterpreter;
      _validateInterpreter();
    } else {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      // 1. Load Vocab
      final vocabStr = await rootBundle.loadString(vocabPath);
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(lines);

      // 2. Load Interpreter
      _interpreter = await Interpreter.fromAsset(modelPath);
      _validateInterpreter();
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      _diagnosticMessage = 'Failed to load model asset ($modelPath): $e';
      if (kDebugMode) {
        debugPrint('LiteRtClassifier failed to initialize: $e');
      }
      _isModelLoaded = false;

      // Ensure tokenizer is loaded even if interpreter fails (so we can test tokenization in fallback)
      if (_tokenizer == null) {
        try {
          final vocabStr = await rootBundle.loadString(vocabPath);
          _tokenizer = WordPieceTokenizer.fromLines(vocabStr.split('\n'));
        } catch (_) {}
      }
    }
  }

  void _validateInterpreter() {
    if (_interpreter == null) {
      _isModelLoaded = false;
      _diagnosticMessage = 'Interpreter is null';
      return;
    }

    try {
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();

      if (inputTensors.isEmpty || outputTensors.isEmpty) {
        _isModelLoaded = false;
        _diagnosticMessage = 'Interpreter has no input/output tensors';
        _closeInterpreter();
        return;
      }

      final outputShape = outputTensors.first.shape;
      // Expect output shape [1, 5] for category classification logits
      // If outputShape is [1, 1] or not matching category classification, it's a regression model or incompatible tensor
      if (outputShape.length != 2 || outputShape[1] != 5) {
        _isModelLoaded = false;
        _diagnosticMessage =
            'Model tensor shape mismatch: expected classification output [1, 5], got $outputShape. Bypassing ML model for fallback heuristics.';
        if (kDebugMode) {
          debugPrint('LiteRtClassifier: $_diagnosticMessage');
        }
        _closeInterpreter();
        return;
      }

      _isModelLoaded = true;
      _diagnosticMessage = 'Classifier model loaded and validated successfully.';
    } catch (e) {
      _isModelLoaded = false;
      _diagnosticMessage = 'Tensor validation error: $e';
      _closeInterpreter();
    }
  }

  void _closeInterpreter() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
  }

  /// Expose model loading status for diagnostics screen.
  bool get isModelLoaded => _isModelLoaded;

  /// Expose diagnostic message for auditing system state.
  String get diagnosticMessage => _diagnosticMessage;

  @override
  Future<AnalysisResult> analyze(AppNotification notification) async {
    final stopwatch = Stopwatch()..start();
    final combinedText = '${notification.title} ${notification.content}';

    // Ensure initialization finished
    if (_tokenizer == null) {
      await _initialize();
    }

    final tokenIds = _tokenizer?.tokenize(combinedText) ?? List<int>.filled(64, 0);

    if (!_isModelLoaded || _interpreter == null) {
      // Graceful fallback heuristic classifier
      final category = _runFallbackHeuristic(combinedText);
      return AnalysisResult(
        category: category,
        score: 0.0, // Zero authentic model confidence for fallback heuristic
        engineName: 'litert_model (fallback)',
        matchedSignals: [
          'Model asset invalid or uninitialized ($_diagnosticMessage)',
          'Tokenizer parsed ${tokenIds.take(5).toList()}...'
        ],
        latencyMs: stopwatch.elapsedMilliseconds,
        isFallback: true,
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
        isFallback: false,
      );
    } catch (e) {
      // Fallback on inference error
      final category = _runFallbackHeuristic(combinedText);
      return AnalysisResult(
        category: category,
        score: 0.0, // Zero authentic model confidence on inference error
        engineName: 'litert_model (fallback on error)',
        matchedSignals: ['Inference error: $e'],
        latencyMs: stopwatch.elapsedMilliseconds,
        isFallback: true,
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
