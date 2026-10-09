import 'package:scope/core/analysis/feature_extractor.dart';

/// Adapter to dynamically adjust feature vectors to match TensorFlow Lite input shapes.
///
/// Pads missing feature slots with default values or truncates excess features
/// to maintain runtime compatibility across retrained models.
class TensorShapeAdapter {
  /// Adapts an extracted numerical feature list to match [targetLength].
  ///
  /// - If [vector] has length equal to [targetLength], it is returned as a list.
  /// - If [vector] has length greater than [targetLength], it is truncated.
  /// - If [vector] has length less than [targetLength], it is padded with [paddingValue].
  static List<double> adapt(
    List<double> vector,
    int targetLength, {
    double paddingValue = 0.0,
  }) {
    if (targetLength <= 0) {
      throw ArgumentError.value(
        targetLength,
        'targetLength',
        'Target length must be a positive integer.',
      );
    }

    if (vector.length == targetLength) {
      return List<double>.from(vector, growable: false);
    }

    if (vector.length > targetLength) {
      return vector.sublist(0, targetLength);
    }

    final padded = List<double>.filled(targetLength, paddingValue);
    for (var i = 0; i < vector.length; i++) {
      padded[i] = vector[i];
    }
    return padded;
  }

  /// Adapts a [FeatureVector] to [targetLength], returning a new [FeatureVector].
  static FeatureVector adaptVector(
    FeatureVector featureVector,
    int targetLength, {
    double paddingValue = 0.0,
  }) {
    final adaptedValues = adapt(
      featureVector.toList(),
      targetLength,
      paddingValue: paddingValue,
    );
    return FeatureVector(adaptedValues);
  }
}
