import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/analysis/analysis_result.dart';
import 'package:scope/core/analysis/notification_analyzer.dart';
import 'package:scope/core/analysis/wordpiece_tokenizer.dart';

/// Classifier using LiteRT (TensorFlow Lite) to classify text categories.
class LiteRtClassifier implements NotificationAnalyzer {
  static const String kExpectedModelHash =
      '63b815ce62f895e48347b9f775c7f529ca56a86733bb3d2601e50889b73d87c6';
  static const String kExpectedVocabHash =
      '6229da7b5527533c901e57b32dafc3c6fd701114a407d1fe4f5da60af3b062c5';

  Interpreter? _interpreter;
  WordPieceTokenizer? _tokenizer;
  bool _isModelLoaded = false;
  bool _integrityViolation = false;
  Future<void>? _initFuture;

  final String modelPath;
  final String vocabPath;
  final String expectedModelHash;
  final String expectedVocabHash;

  LiteRtClassifier({
    Interpreter? interpreter,
    this.modelPath = 'assets/model.tflite',
    this.vocabPath = 'assets/vocab.txt',
    this.expectedModelHash = kExpectedModelHash,
    this.expectedVocabHash = kExpectedVocabHash,
  }) : _interpreter = interpreter {
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    try {
      _integrityViolation = false;

      // 1. Load Vocab Bytes & Cryptographic Hash Validation
      final vocabByteData = await rootBundle.load(vocabPath);
      final vocabBytes = vocabByteData.buffer.asUint8List(
        vocabByteData.offsetInBytes,
        vocabByteData.lengthInBytes,
      );
      final actualVocabHash = sha256.convert(vocabBytes).toString();

      if (actualVocabHash.toLowerCase() != expectedVocabHash.toLowerCase()) {
        // ignore: avoid_print
        print(
          'Asset integrity violation: Vocab SHA-256 mismatch. '
          'Expected: $expectedVocabHash, Actual: $actualVocabHash',
        );
        _integrityViolation = true;
        _isModelLoaded = false;
        return;
      }

      final vocabStr = utf8.decode(vocabBytes);
      final lines = vocabStr.split('\n');
      _tokenizer = WordPieceTokenizer.fromLines(lines);

      // 2. Load Model Bytes & Cryptographic Hash Validation
      final modelByteData = await rootBundle.load(modelPath);
      final modelBytes = modelByteData.buffer.asUint8List(
        modelByteData.offsetInBytes,
        modelByteData.lengthInBytes,
      );
      final actualModelHash = sha256.convert(modelBytes).toString();

      if (actualModelHash.toLowerCase() != expectedModelHash.toLowerCase()) {
        // ignore: avoid_print
        print(
          'Asset integrity violation: Model SHA-256 mismatch. '
          'Expected: $expectedModelHash, Actual: $actualModelHash',
        );
        _integrityViolation = true;
        _isModelLoaded = false;
        return;
      }

      // 3. Load Interpreter upon successful SHA-256 asset validation
      _interpreter ??= await Interpreter.fromAsset(modelPath);
      _isModelLoaded = true;
    } catch (e) {
      // Graceful degradation: Log and set flags so analyze runs in fallback mode
      // ignore: avoid_print
      print('LiteRtClassifier failed to initialize: $e');
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

  /// Expose model loading status for diagnostics screen.
  bool get isModelLoaded => _isModelLoaded;

  /// Expose integrity violation status.
  bool get isIntegrityViolation => _integrityViolation;

  @override
  Future<AnalysisResult> analyze(AppNotification notification) async {
    final stopwatch = Stopwatch()..start();
    final combinedText = '${notification.title} ${notification.content}';

    // Ensure initialization finished
    if (_initFuture != null) {
      await _initFuture;
    } else if (_tokenizer == null) {
      await _initialize();
    }

    final tokenIds =
        _tokenizer?.tokenize(combinedText) ?? List<int>.filled(64, 0);

    if (_integrityViolation) {
      final category = _runFallbackHeuristic(combinedText);
      return AnalysisResult(
        category: category,
        score: 0.50,
        engineName: 'litert_model (fallback - integrity alert)',
        matchedSignals: [
          'Asset SHA-256 integrity violation detected',
          'Tokenizer parsed ${tokenIds.take(5).toList()}...'
        ],
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }

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
