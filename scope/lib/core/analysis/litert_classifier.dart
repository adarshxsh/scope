import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';
import 'package:scope/core/analysis/asset_verifier.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;
  final AssetBundle? _assetBundle;

  LiteRtClassifier({Interpreter? interpreter, AssetBundle? assetBundle})
      : _interpreter = interpreter,
        _assetBundle = assetBundle,
        _isModelLoaded = interpreter != null {
    if (interpreter == null) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      final bundle = _assetBundle ?? rootBundle;

      // 1. Verify SHA-256 digests prior to loading assets
      await AssetVerifier.verifyAsset('assets/vocab.txt', bundle: bundle);
      await AssetVerifier.verifyAsset('assets/model.tflite', bundle: bundle);
      await AssetVerifier.verifyAsset('assets/rules.json', bundle: bundle);

      // 2. Load Vocab
      final vocabStr = await bundle.loadString('assets/vocab.txt');
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(lines);

      // 3. Load Interpreter from assets
      if (_assetBundle != null) {
        final bytes = await AssetVerifier.verifyAndLoadBytes('assets/model.tflite', bundle: _assetBundle);
        _interpreter = Interpreter.fromBuffer(bytes);
      } else {
        _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      }
      _isModelLoaded = _interpreter != null;
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      // ignore: avoid_print
      print('LiteRtClassifier failed to initialize: $e');
      _isModelLoaded = false;

      // Ensure tokenizer is loaded even if interpreter fails (so we can test tokenization in fallback)
      if (_tokenizer == null) {
        try {
          final vocabStr = await (_assetBundle ?? rootBundle).loadString('assets/vocab.txt');
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
    if (_tokenizer == null && !_isModelLoaded) {
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
          'Model asset invalid or uninitialized',
          'Tokenizer parsed ${tokenIds.take(5).toList()}...'
        ],
        latencyMs: stopwatch.elapsedMilliseconds,
        isFallback: true,
      );
    }

    try {
      // Inspect model tensor shapes adaptively
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final targetLen = (inputShape.isNotEmpty && inputShape.last > 0) ? inputShape.last : 64;
      final adjustedTokens = tokenIds.length == targetLen
          ? tokenIds
          : (tokenIds.length > targetLen
              ? tokenIds.sublist(0, targetLen)
              : [...tokenIds, ...List<int>.filled(targetLen - tokenIds.length, 0)]);
      final input = [adjustedTokens];

      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final numClasses = (outputShape.isNotEmpty && outputShape.last > 0) ? outputShape.last : 5;
      final output = List<double>.filled(numClasses, 0.0).reshape([1, numClasses]);

      _interpreter!.run(input, output);

      List<double> rawScores = List<double>.from(output[0] as List);
      if (rawScores.length < 5) {
        rawScores = [...rawScores, ...List<double>.filled(5 - rawScores.length, 0.0)];
      } else if (rawScores.length > 5) {
        rawScores = rawScores.sublist(0, 5);
      }

      final softmaxScores = _softmax(rawScores);

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
