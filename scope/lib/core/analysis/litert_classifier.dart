import 'dart:convert';
import 'dart:math' as math;
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

  LiteRtClassifier() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // 1. Load Vocab
      final vocabStr = await rootBundle.loadString('assets/vocab.txt');
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(lines);

      // 2. Load manifest and verify model bytes
      final manifest = await AssetVerifier.loadManifest();
      final ByteData modelData = await rootBundle.load('assets/model.tflite');
      final Uint8List modelBytes = modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );

      await initializeFromBytes(
        modelBytes,
        vocabBytes: utf8.encode(vocabStr),
        manifestMap: manifest,
      );
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      // ignore: avoid_print
      print('LiteRtClassifier failed to initialize: $e');
      _isModelLoaded = false;
      _interpreter = null;

      // Ensure tokenizer is loaded even if interpreter fails (so we can test tokenization in fallback)
      if (_tokenizer == null) {
        try {
          final vocabStr = await rootBundle.loadString('assets/vocab.txt');
          _tokenizer = WordPieceTokenizer.fromLines(vocabStr.split('\n'));
        } catch (_) {}
      }
    }
  }

  /// Initializes classifier from provided model byte buffer and manifest map.
  /// Validates model buffer SHA-256 checksum before interpreter instantiation.
  Future<void> initializeFromBytes(
    Uint8List modelBytes, {
    Uint8List? vocabBytes,
    Map<String, String>? manifestMap,
  }) async {
    try {
      if (vocabBytes != null) {
        final vocabStr = utf8.decode(vocabBytes);
        _tokenizer = WordPieceTokenizer.fromLines(vocabStr.split('\n'));
      } else if (_tokenizer == null) {
        final vocabStr = await rootBundle.loadString('assets/vocab.txt');
        _tokenizer = WordPieceTokenizer.fromLines(vocabStr.split('\n'));
      }

      final manifest = manifestMap ?? await AssetVerifier.loadManifest();

      final isVerified = AssetVerifier.verifyBuffer(
        modelBytes,
        'assets/model.tflite',
        manifest: manifest,
      );

      if (!isVerified) {
        // Verification failed
        _isModelLoaded = false;
        _interpreter = null;
        return;
      }

      // Instantiate interpreter from verified model bytes
      _interpreter = Interpreter.fromBuffer(modelBytes);
      _isModelLoaded = true;
    } catch (e) {
      // ignore: avoid_print
      print('LiteRtClassifier: Interpreter creation or verification failed: $e');
      _isModelLoaded = false;
      _interpreter = null;
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
      // Run model inference dynamically based on tensor shapes
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      List<dynamic> input;
      if (inputShape.length >= 2 && inputShape[1] == 63) {
        final featureVector = FeatureExtractor.extractFromAppNotification(notification);
        input = [featureVector];
      } else {
        input = [tokenIds];
      }

      int numClasses = outputShape.length >= 2 ? outputShape[1] : 5;
      final output = List<double>.filled(numClasses, 0.0).reshape([1, numClasses]);

      _interpreter!.run(input, output);

      if (numClasses == 5) {
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
      } else {
        final rawVal = (output[0][0] as num).toDouble();
        final score = (rawVal > 1.0 ? rawVal / 100.0 : rawVal).clamp(0.0, 1.0);
        final category = _runFallbackHeuristic(combinedText);
        return AnalysisResult(
          category: category,
          score: score,
          engineName: 'litert_model',
          matchedSignals: ['Model predicted score: $score'],
          latencyMs: stopwatch.elapsedMilliseconds,
          isFallback: false,
        );
      }
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
