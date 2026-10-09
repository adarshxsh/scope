import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';
import 'package:scope/core/utils/asset_integrity_guard.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;
  Future<void>? _initFuture;

  final AssetBundle? _assetBundle;
  final Map<String, String>? _customExpectedHashes;

  LiteRtClassifier({
    AssetBundle? assetBundle,
    Map<String, String>? customExpectedHashes,
    Interpreter? interpreter,
    WordPieceTokenizer? tokenizer,
  })  : _assetBundle = assetBundle,
        _customExpectedHashes = customExpectedHashes,
        _interpreter = interpreter,
        _tokenizer = tokenizer,
        _isModelLoaded = interpreter != null {
    if (_interpreter == null) {
      _initFuture = _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      final bundle = _assetBundle ?? rootBundle;

      // 1. Load and verify assets/vocab.txt via SHA-256 integrity guard
      const vocabPath = 'assets/vocab.txt';
      final ByteData vocabData = await bundle.load(vocabPath);
      final Uint8List vocabBytes = vocabData.buffer.asUint8List(
        vocabData.offsetInBytes,
        vocabData.lengthInBytes,
      );

      final isVocabValid = AssetIntegrityGuard.verifyAssetBytes(
        vocabPath,
        vocabBytes,
        expectedHash: _customExpectedHashes?[vocabPath],
      );

      if (!isVocabValid) {
        debugPrint('LiteRtClassifier: SHA-256 integrity check failed for $vocabPath');
        _isModelLoaded = false;
        return;
      }

      final vocabStr = utf8.decode(vocabBytes);
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(lines);

      // 2. Load and verify assets/model.tflite via SHA-256 integrity guard
      const modelPath = 'assets/model.tflite';
      final ByteData modelData = await bundle.load(modelPath);
      final Uint8List modelBytes = modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );

      final isModelValid = AssetIntegrityGuard.verifyAssetBytes(
        modelPath,
        modelBytes,
        expectedHash: _customExpectedHashes?[modelPath],
      );

      if (!isModelValid) {
        debugPrint('LiteRtClassifier: SHA-256 integrity check failed for $modelPath');
        _isModelLoaded = false;
        return;
      }

      // 3. Instantiate TFLite interpreter from verified buffer
      _interpreter = Interpreter.fromBuffer(modelBytes);
      _isModelLoaded = true;
      debugPrint('LiteRtClassifier: Model verified and loaded successfully.');
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      debugPrint('LiteRtClassifier failed to initialize: $e');
      _isModelLoaded = false;
      _interpreter = null;

      // Ensure tokenizer is loaded if possible even if interpreter fails
      if (_tokenizer == null) {
        try {
          final bundle = _assetBundle ?? rootBundle;
          final ByteData vocabData = await bundle.load('assets/vocab.txt');
          final Uint8List vocabBytes = vocabData.buffer.asUint8List(
            vocabData.offsetInBytes,
            vocabData.lengthInBytes,
          );
          _tokenizer = WordPieceTokenizer.fromLines(utf8.decode(vocabBytes).split('\n'));
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
    if (_initFuture != null) {
      await _initFuture;
    } else if (_tokenizer == null && !_isModelLoaded) {
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
