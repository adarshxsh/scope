import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';
import 'package:scope/core/analysis/asset_verifier_service.dart';
import 'package:scope/core/analysis/asset_integrity.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;
  Future<void>? _initFuture;

  LiteRtClassifier({Map<String, String>? customHashes}) {
    _initFuture = _initialize(customHashes: customHashes);
  }

  /// Explicit initialization method for tests or callers requiring custom asset hashes.
  Future<void> initialize({Map<String, String>? customHashes}) async {
    _initFuture = _initialize(customHashes: customHashes);
    await _initFuture;
  }

  Future<void> _initialize({Map<String, String>? customHashes}) async {
    try {
      // 1. Load & verify Vocab asset
      bool isVocabVerified = false;
      if (customHashes != null) {
        try {
          final vocabData = await rootBundle.load('assets/vocab.txt');
          final vocabBytes = vocabData.buffer.asUint8List(vocabData.offsetInBytes, vocabData.lengthInBytes);
          isVocabVerified = AssetIntegrity.verify('assets/vocab.txt', vocabBytes, customHashes: customHashes);
        } catch (_) {
          isVocabVerified = false;
        }
      } else {
        isVocabVerified = await AssetVerifierService.instance.verifyAsset('assets/vocab.txt');
      }

      if (isVocabVerified) {
        final vocabStr = await rootBundle.loadString('assets/vocab.txt');
        final lines = vocabStr.split('\n');
        _tokenizer = WordPieceTokenizer.fromLines(lines);
      } else {
        debugPrint('LiteRtClassifier: Asset verification failed for assets/vocab.txt.');
      }

      // 2. Load & verify Model asset
      bool isModelVerified = false;
      if (customHashes != null) {
        try {
          final modelData = await rootBundle.load('assets/model.tflite');
          final modelBytes = modelData.buffer.asUint8List(modelData.offsetInBytes, modelData.lengthInBytes);
          isModelVerified = AssetIntegrity.verify('assets/model.tflite', modelBytes, customHashes: customHashes);
        } catch (_) {
          isModelVerified = false;
        }
      } else {
        isModelVerified = await AssetVerifierService.instance.verifyAsset('assets/model.tflite');
      }

      if (isModelVerified) {
        _isModelLoaded = false; // Model is look-again regression model in GhostAI
      } else {
        _isModelLoaded = false;
        debugPrint('LiteRtClassifier: Asset verification failed for assets/model.tflite.');
      }
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      debugPrint('LiteRtClassifier failed to initialize: $e');
      _isModelLoaded = false;

      // Ensure tokenizer is loaded even if interpreter fails (so we can test tokenization in fallback)
      if (_tokenizer == null) {
        try {
          bool isVocabVerified = false;
          if (customHashes != null) {
            try {
              final vocabData = await rootBundle.load('assets/vocab.txt');
              final vocabBytes = vocabData.buffer.asUint8List(vocabData.offsetInBytes, vocabData.lengthInBytes);
              isVocabVerified = AssetIntegrity.verify('assets/vocab.txt', vocabBytes, customHashes: customHashes);
            } catch (_) {}
          } else {
            isVocabVerified = await AssetVerifierService.instance.verifyAsset('assets/vocab.txt');
          }

          if (isVocabVerified) {
            final vocabStr = await rootBundle.loadString('assets/vocab.txt');
            _tokenizer = WordPieceTokenizer.fromLines(vocabStr.split('\n'));
          }
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
    }
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
