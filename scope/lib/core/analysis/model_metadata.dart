import 'dart:convert';

/// Represents tensor specification and metadata for ML classification models.
class ModelMetadata {
  final String modelName;
  final String version;
  final List<int> inputShape;
  final List<int> outputShape;
  final String dataType;
  final String? description;

  const ModelMetadata({
    required this.modelName,
    required this.version,
    required this.inputShape,
    required this.outputShape,
    this.dataType = 'float32',
    this.description,
  });

  /// Default baseline model metadata contract specification.
  factory ModelMetadata.defaultBaseline() {
    return const ModelMetadata(
      modelName: 'ghost_ai_baseline',
      version: '1.0.0-baseline',
      inputShape: [1, 63],
      outputShape: [1, 1],
      dataType: 'float32',
      description: 'Default bundled baseline look-again classification model.',
    );
  }

  /// Parses ModelMetadata from a JSON Map.
  factory ModelMetadata.fromMap(Map<String, dynamic> map) {
    List<int> parseShape(dynamic value) {
      if (value is List) {
        return value.map((e) => (e as num).toInt()).toList();
      }
      return [1, 63];
    }

    final inputMap = map['input_tensor'] as Map<String, dynamic>?;
    final outputMap = map['output_tensor'] as Map<String, dynamic>?;

    final inputShape = inputMap != null && inputMap['shape'] != null
        ? parseShape(inputMap['shape'])
        : (map['input_shape'] != null ? parseShape(map['input_shape']) : [1, 63]);

    final outputShape = outputMap != null && outputMap['shape'] != null
        ? parseShape(outputMap['shape'])
        : (map['output_shape'] != null ? parseShape(map['output_shape']) : [1, 1]);

    return ModelMetadata(
      modelName: map['model_name'] as String? ?? map['name'] as String? ?? 'unknown_model',
      version: map['version'] as String? ?? '1.0.0',
      inputShape: inputShape,
      outputShape: outputShape,
      dataType: map['data_type'] as String? ?? inputMap?['type'] as String? ?? 'float32',
      description: map['description'] as String?,
    );
  }

  /// Parses ModelMetadata from a JSON string.
  factory ModelMetadata.fromJson(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return ModelMetadata.fromMap(map);
  }

  /// Converts ModelMetadata to a JSON Map.
  Map<String, dynamic> toMap() {
    return {
      'model_name': modelName,
      'version': version,
      'input_shape': inputShape,
      'output_shape': outputShape,
      'input_tensor': {
        'name': 'features',
        'shape': inputShape,
        'type': dataType,
      },
      'output_tensor': {
        'name': 'score',
        'shape': outputShape,
        'type': dataType,
      },
      'data_type': dataType,
      'description': description,
    };
  }

  /// Converts ModelMetadata to a JSON string.
  String toJson() => jsonEncode(toMap());

  /// Validates the model metadata schema contract against required tensor dimensions.
  /// Strict Contract Enforcement:
  /// - Expected input tensor feature dimension must be 63 (e.g. shape [1, 63]).
  /// - Input shape must be non-empty.
  /// - Output shape must be non-empty.
  bool validateSchema({
    List<int> expectedInputShape = const [1, 63],
    int expectedFeatureCount = 63,
  }) {
    if (inputShape.isEmpty || outputShape.isEmpty) {
      return false;
    }

    // Check last dimension (feature vector dimension)
    final actualFeatureCount = inputShape.last;
    if (actualFeatureCount != expectedFeatureCount) {
      return false;
    }

    // If input shape length matches expected, ensure batch dimension is valid (>= 1)
    if (inputShape.length == expectedInputShape.length) {
      if (inputShape[0] < 1) return false;
    }

    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModelMetadata &&
        other.modelName == modelName &&
        other.version == version &&
        _listEquals(other.inputShape, inputShape) &&
        _listEquals(other.outputShape, outputShape) &&
        other.dataType == dataType;
  }

  @override
  int get hashCode => Object.hash(
        modelName,
        version,
        Object.hashAll(inputShape),
        Object.hashAll(outputShape),
        dataType,
      );

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
