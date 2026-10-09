import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  final Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;
  Map<String, dynamic>? _metadata;

  LiteRtClassifier({
    Interpreter? interpreter,
    Map<String, dynamic>? metadata,
  })  : _interpreter = interpreter,
        _metadata = metadata {
    if (_interpreter != null) {
      _isModelLoaded = true;
    }
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // 1. Load Vocab
      if (_tokenizer == null) {
        final vocabStr = await rootBundle.loadString('assets/vocab.txt');
        final lines = vocabStr.split('\n');
        _tokenizer = WordPieceTokenizer.fromLines(lines);
      }

      // Load optional dynamic metadata JSON header if not provided
      if (_metadata == null) {
        try {
          final metaStr = await rootBundle.loadString('assets/metadata.json');
          _metadata = json.decode(metaStr) as Map<String, dynamic>;
        } catch (_) {}
      }

      // 2. Load Interpreter if not supplied
      if (_interpreter == null) {
        // Bypassed default asset interpreter loading unless provided or configured
      }
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      // ignore: avoid_print
      print('LiteRtClassifier failed to initialize: $e');
      if (_interpreter == null) {
        _isModelLoaded = false;
      }

      // Ensure tokenizer is loaded even if interpreter fails
      if (_tokenizer == null) {
        try {
          final vocabStr = await rootBundle.loadString('assets/vocab.txt');
          _tokenizer = WordPieceTokenizer.fromLines(vocabStr.split('\n'));
        } catch (_) {}
      }
    }
  }

  /// Exposes model metadata headers.
  Map<String, dynamic>? get metadata => _metadata;

  /// Sets model metadata manually.
  void setMetadata(Map<String, dynamic> metadata) {
    _metadata = Map<String, dynamic>.from(metadata);
  }

  /// Queries the expected input vector dimension from model metadata or input tensor shape.
  int get inputVectorDimension {
    if (_metadata != null) {
      if (_metadata!['feature_vector_size'] is int) {
        return _metadata!['feature_vector_size'] as int;
      }
      if (_metadata!['input_vector_dimension'] is int) {
        return _metadata!['input_vector_dimension'] as int;
      }
      if (_metadata!['flutter'] is Map && _metadata!['flutter']['input_shape'] is List) {
        final shape = _metadata!['flutter']['input_shape'] as List;
        if (shape.length >= 2 && shape[1] is int) {
          return shape[1] as int;
        }
      }
    }
    final interpreter = _interpreter;
    if (interpreter != null) {
      try {
        final shape = interpreter.getInputTensor(0).shape;
        if (shape.length >= 2 && shape[1] > 0) {
          return shape[1];
        }
      } catch (_) {}
    }
    return 128; // Default dimension for backwards compatibility
  }

  /// Expose model loading status for diagnostics screen.
  bool get isModelLoaded => _isModelLoaded;

  @override
  Future<AnalysisResult> analyze(AppNotification notification) async {
    final stopwatch = Stopwatch()..start();
    final combinedText = '${notification.title} ${notification.content}';

    // Ensure initialization finished
    if (_tokenizer == null) {
      await _initialize();
    }

    final tokenIds = _tokenizer?.tokenize(combinedText) ?? List<int>.filled(64, 0);

    final interpreter = _interpreter;
    if (!_isModelLoaded || interpreter == null) {
      // Graceful fallback heuristic classifier
      final category = _runFallbackHeuristic(combinedText);
      return AnalysisResult(
        category: category,
        score: 0.0, // Zero authentic model confidence for fallback heuristic
        engineName: 'litert_model (fallback)',
        matchedSignals: [
          'Model asset invalid or uninitialized',
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

      interpreter.run(input, output);

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
