import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Represents a Reinforcement Learning from Human Feedback (RLHF) sample logged on-device.
class RLHFFeedbackSample {
  final String id;
  final String notificationId;
  final String packageName;
  final String title;
  final String content;
  final List<double> featureVector;
  final String predictedCategory;
  final String predictedPriority;
  final double predictedScore;
  final double rewardSignal; // +1.0 for reward, -1.0 for penalty
  final String? correctedCategory;
  final String? correctedPriority;
  final double? correctedScore;
  final String modelVersion;
  final String ruleVersion;
  final int timestamp;

  RLHFFeedbackSample({
    required this.id,
    required this.notificationId,
    required this.packageName,
    required this.title,
    required this.content,
    required this.featureVector,
    required this.predictedCategory,
    required this.predictedPriority,
    required this.predictedScore,
    required this.rewardSignal,
    this.correctedCategory,
    this.correctedPriority,
    this.correctedScore,
    required this.modelVersion,
    required this.ruleVersion,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'notification_id': notificationId,
      'package_name': packageName,
      'title': title,
      'content': content,
      'feature_vector': featureVector,
      'predicted_category': predictedCategory,
      'predicted_priority': predictedPriority,
      'predicted_score': predictedScore,
      'reward_signal': rewardSignal,
      'corrected_category': correctedCategory,
      'corrected_priority': correctedPriority,
      'corrected_score': correctedScore,
      'model_version': modelVersion,
      'rule_version': ruleVersion,
      'timestamp': timestamp,
    };
  }

  factory RLHFFeedbackSample.fromJson(Map<String, dynamic> json) {
    return RLHFFeedbackSample(
      id: json['id'] as String? ?? '',
      notificationId: json['notification_id'] as String? ?? '',
      packageName: json['package_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      featureVector: (json['feature_vector'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      predictedCategory: json['predicted_category'] as String? ?? 'unknown',
      predictedPriority: json['predicted_priority'] as String? ?? 'medium',
      predictedScore: (json['predicted_score'] as num?)?.toDouble() ?? 0.0,
      rewardSignal: (json['reward_signal'] as num?)?.toDouble() ?? 0.0,
      correctedCategory: json['corrected_category'] as String?,
      correctedPriority: json['corrected_priority'] as String?,
      correctedScore: (json['corrected_score'] as num?)?.toDouble(),
      modelVersion: json['model_version'] as String? ?? '1.0.0-tflite',
      ruleVersion: json['rule_version'] as String? ?? '1.0.0',
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Central manager for AttentionOS model lifecycle, OTA dynamic updates,
/// version negotiation, candidate validation, and RLHF feedback logging.
class ModelLifecycleManager {
  static ModelLifecycleManager? _instance;
  Directory? _customBaseDir;

  static const String defaultAssetVersion = '1.0.0-tflite';
  String _activeVersion = defaultAssetVersion;
  File? _activeModelFile;

  final List<RLHFFeedbackSample> _inMemoryFeedbackSamples = [];

  ModelLifecycleManager._();

  static ModelLifecycleManager get instance => _instance ??= ModelLifecycleManager._();

  /// Allows setting a custom directory for testing or custom persistence.
  void setCustomBaseDirectory(Directory dir) {
    _customBaseDir = dir;
  }

  /// Current active model version.
  String get activeVersion => _activeVersion;

  /// Active model file on disk if loaded dynamically, null if using asset.
  File? get activeModelFile => _activeModelFile;

  /// Total number of logged RLHF samples in memory.
  int get feedbackSamplesCount => _inMemoryFeedbackSamples.length;

  /// Returns read-only view of in-memory feedback samples.
  List<RLHFFeedbackSample> get feedbackSamples => List.unmodifiable(_inMemoryFeedbackSamples);

  /// Initializes the model lifecycle manager state on startup.
  Future<void> initialize() async {
    try {
      final baseDir = await _getStorageDirectory();
      final metadataFile = File(p.join(baseDir.path, 'active_model_metadata.json'));
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final metadata = jsonDecode(content) as Map<String, dynamic>;
        final version = metadata['version'] as String?;
        final modelPath = metadata['model_path'] as String?;

        if (version != null && modelPath != null) {
          final modelFile = File(modelPath);
          if (await modelFile.exists()) {
            _activeModelFile = modelFile;
            _activeVersion = version;
            debugPrint('ModelLifecycleManager: Restored dynamic model v$_activeVersion from $modelPath');
          }
        }
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error during startup initialization: $e');
    }

    await loadFeedbackSamples();
  }

  /// Validates a candidate TFLite model binary and its version before deployment.
  Future<bool> validateCandidateModel({
    required Uint8List modelBytes,
    required String candidateVersion,
    int expectedInputSize = 63,
  }) async {
    if (modelBytes.isEmpty) {
      debugPrint('ModelLifecycleManager Validation Error: Empty model bytes.');
      return false;
    }

    // Version negotiation: compare versions if active version follows semver
    if (!_isVersionEligible(candidateVersion, _activeVersion)) {
      debugPrint(
          'ModelLifecycleManager Validation Error: Candidate version ($candidateVersion) is not newer/eligible compared to active version ($_activeVersion).');
      return false;
    }

    // Tensor shape and interpreter allocation test
    try {
      final interpreter = Interpreter.fromBuffer(modelBytes);
      final inputDetails = interpreter.getInputTensors();
      final outputDetails = interpreter.getOutputTensors();

      if (inputDetails.isEmpty || outputDetails.isEmpty) {
        interpreter.close();
        debugPrint('ModelLifecycleManager Validation Error: Missing input or output tensors.');
        return false;
      }

      final inputShape = inputDetails[0].shape;
      final outputShape = outputDetails[0].shape;

      // Verify input shape: [1, 63] or [63]
      final lastDim = inputShape.last;
      if (lastDim != expectedInputSize) {
        interpreter.close();
        debugPrint(
            'ModelLifecycleManager Validation Error: Input dimension mismatch. Expected $expectedInputSize, got $lastDim (shape: $inputShape).');
        return false;
      }

      // Verify output shape: scalar or [1, 1]
      final outDim = outputShape.last;
      if (outDim != 1) {
        interpreter.close();
        debugPrint('ModelLifecycleManager Validation Error: Output dimension mismatch. Expected 1, got $outDim.');
        return false;
      }

      interpreter.close();
      debugPrint('ModelLifecycleManager Validation: Candidate model v$candidateVersion passed all checks.');
      return true;
    } catch (e) {
      debugPrint('ModelLifecycleManager Validation Error: Failed to instantiate interpreter for candidate model: $e');
      return false;
    }
  }

  /// Deploys an over-the-air (OTA) dynamic model update.
  Future<bool> deployModelUpdate({
    required Uint8List modelBytes,
    required String version,
    Map<String, dynamic>? metadata,
  }) async {
    final isValid = await validateCandidateModel(
      modelBytes: modelBytes,
      candidateVersion: version,
    );

    if (!isValid) return false;

    try {
      final baseDir = await _getStorageDirectory();
      final modelsDir = Directory(p.join(baseDir.path, 'models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final targetFile = File(p.join(modelsDir.path, 'ghost_ai_v$version.tflite'));
      await targetFile.writeAsBytes(modelBytes, flush: true);

      final metadataFile = File(p.join(baseDir.path, 'active_model_metadata.json'));
      final metaContent = {
        'version': version,
        'model_path': targetFile.path,
        'deployed_at': DateTime.now().toIso8601String(),
        'custom_metadata': metadata ?? {},
      };
      await metadataFile.writeAsString(jsonEncode(metaContent), flush: true);

      _activeModelFile = targetFile;
      _activeVersion = version;

      debugPrint('ModelLifecycleManager: Successfully deployed model update v$version');
      return true;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error deploying model update: $e');
      return false;
    }
  }

  /// Rollback active model to the default bundled asset.
  Future<void> rollbackToDefaultAsset() async {
    try {
      final baseDir = await _getStorageDirectory();
      final metadataFile = File(p.join(baseDir.path, 'active_model_metadata.json'));
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }
      _activeModelFile = null;
      _activeVersion = defaultAssetVersion;
      debugPrint('ModelLifecycleManager: Rolled back to default asset model ($defaultAssetVersion).');
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error during rollback: $e');
    }
  }

  /// Logs a training sample / reward signal from user interaction (RLHF).
  Future<void> logFeedbackSample(RLHFFeedbackSample sample) async {
    _inMemoryFeedbackSamples.add(sample);
    try {
      final baseDir = await _getStorageDirectory();
      final file = File(p.join(baseDir.path, 'rlhf_samples.jsonl'));
      final line = '${jsonEncode(sample.toJson())}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      debugPrint('ModelLifecycleManager: Logged RLHF sample ${sample.id} (reward: ${sample.rewardSignal})');
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error persisting RLHF sample: $e');
    }
  }

  /// Loads persisted RLHF samples from local disk.
  Future<List<RLHFFeedbackSample>> loadFeedbackSamples() async {
    try {
      final baseDir = await _getStorageDirectory();
      final file = File(p.join(baseDir.path, 'rlhf_samples.jsonl'));
      if (!await file.exists()) {
        return [];
      }
      final lines = await file.readAsLines();
      final samples = <RLHFFeedbackSample>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          samples.add(RLHFFeedbackSample.fromJson(json));
        } catch (_) {}
      }
      _inMemoryFeedbackSamples.clear();
      _inMemoryFeedbackSamples.addAll(samples);
      return samples;
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error loading RLHF samples: $e');
      return [];
    }
  }

  /// Exports logged RLHF samples in JSONL format for offline Python training.
  Future<String> exportFeedbackDatasetJsonl() async {
    final samples = await loadFeedbackSamples();
    final buffer = StringBuffer();
    for (final s in samples) {
      buffer.writeln(jsonEncode(s.toJson()));
    }
    return buffer.toString();
  }

  /// Clears in-memory and persisted RLHF samples (for testing or reset).
  Future<void> clearFeedbackSamples() async {
    _inMemoryFeedbackSamples.clear();
    try {
      final baseDir = await _getStorageDirectory();
      final file = File(p.join(baseDir.path, 'rlhf_samples.jsonl'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('ModelLifecycleManager: Error clearing RLHF samples: $e');
    }
  }

  Future<Directory> _getStorageDirectory() async {
    if (_customBaseDir != null) return _customBaseDir!;
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  bool _isVersionEligible(String candidate, String current) {
    if (candidate == current) return true;
    try {
      final cParts = candidate.split('-')[0].split('.').map(int.parse).toList();
      final curParts = current.split('-')[0].split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final c = i < cParts.length ? cParts[i] : 0;
        final cur = i < curParts.length ? curParts[i] : 0;
        if (c > cur) return true;
        if (c < cur) return false;
      }
      return true;
    } catch (_) {
      // Fall back to string comparison if not strict semver
      return candidate.compareTo(current) >= 0;
    }
  }
}
