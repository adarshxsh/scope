import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';
import 'package:scope/core/analysis/asset_verifier.dart';
import 'package:scope/core/analysis/feature_extractor.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;
  String? _verificationError;

  LiteRtClassifier() {
    _initialize();
  }

  /// Reinitializes classifier with optional custom bytes (used for testing asset corruption).
  Future<void> reinitialize({Uint8List? modelBytes, Uint8List? vocabBytes}) async {
    await _initialize(modelBytes: modelBytes, vocabBytes: vocabBytes);
  }

  Future<void> _initialize({Uint8List? modelBytes, Uint8List? vocabBytes}) async {
    _verificationError = null;
    try {
      // 1. Load Vocab and verify SHA-256
      final Uint8List vBytes;
      if (vocabBytes != null) {
        vBytes = vocabBytes;
      } else {
        final vocabData = await rootBundle.load('assets/vocab.txt');
        vBytes = vocabData.buffer.asUint8List();
      }
      AssetVerifier.verifyAsset('assets/vocab.txt', vBytes);

      final vocabStr = utf8.decode(vBytes);
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(lines);

      // 2. Load Interpreter from verified assets/model.tflite bytes
      final Uint8List mBytes;
      if (modelBytes != null) {
        mBytes = modelBytes;
      } else {
        final modelData = await rootBundle.load('assets/model.tflite');
        mBytes = modelData.buffer.asUint8List();
      }
      AssetVerifier.verifyAsset('assets/model.tflite', mBytes);

      _interpreter = Interpreter.fromBuffer(mBytes);
      _isModelLoaded = true;
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      // ignore: avoid_print
      print('LiteRtClassifier failed to initialize: $e');
      _isModelLoaded = false;
      _verificationError = e.toString();

      // Ensure tokenizer is loaded even if interpreter fails (so we can test tokenization in fallback)
      if (_tokenizer == null) {
        try {
          final vocabData = await rootBundle.load('assets/vocab.txt');
          final vBytes = vocabData.buffer.asUint8List();
          AssetVerifier.verifyAsset('assets/vocab.txt', vBytes);
          _tokenizer = WordPieceTokenizer.fromLines(utf8.decode(vBytes).split('\n'));
        } catch (_) {}
      }
    }
  }

  /// Expose model loading status for diagnostics screen.
  bool get isModelLoaded => _isModelLoaded;

  /// Expose last verification failure message if any.
  String? get verificationError => _verificationError;

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
      final matchedSignals = <String>[];
      if (_verificationError != null) {
        matchedSignals.add('Asset verification failed: $_verificationError');
      } else {
        matchedSignals.add('Model asset invalid or uninitialized');
      }
      matchedSignals.add('Tokenizer parsed ${tokenIds.take(5).toList()}...');

      return AnalysisResult(
        category: category,
        score: 0.0, // Zero authentic model confidence for fallback heuristic
        engineName: 'litert_model (fallback)',
        matchedSignals: matchedSignals,
        latencyMs: stopwatch.elapsedMilliseconds,
        isFallback: true,
      );
    }

    try {
      // Run model inference dynamically inspecting tensor shapes
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      String predictedCategory;
      double maxScore;

      if (outputShape.length >= 2 && outputShape[1] == 5) {
        final input = inputShape[1] == 63
            ? [FeatureExtractor.extractFromAppNotification(notification)]
            : [tokenIds];
        final output = List<double>.filled(5, 0.0).reshape([1, 5]);

        _interpreter!.run(input, output);

        final scores = List<double>.from(output[0] as List);
        final softmaxScores = _softmax(scores);

        int bestIndex = 0;
        maxScore = -1.0;
        for (int i = 0; i < softmaxScores.length; i++) {
          if (softmaxScores[i] > maxScore) {
            maxScore = softmaxScores[i];
            bestIndex = i;
          }
        }

        final categories = ['promo', 'social', 'sys', 'msg', 'finance'];
        predictedCategory = categories[bestIndex];
      } else {
        final featureVector = FeatureExtractor.extractFromAppNotification(notification);
        final input = [featureVector];
        final output = List<double>.filled(1, 0.0).reshape([1, 1]);

        _interpreter!.run(input, output);

        final rawScore = output[0][0] as double;
        maxScore = (rawScore / 100.0).clamp(0.0, 1.0);
        predictedCategory = _runFallbackHeuristic(combinedText);
      }

      return AnalysisResult(
        category: predictedCategory,
        score: maxScore,
        engineName: 'litert_model',
        matchedSignals: ['Model inference executed successfully'],
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
