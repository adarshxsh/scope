import 'package:flutter_test/flutter_test.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/tensor_shape_adapter.dart';

void main() {
  group('TensorShapeAdapter Unit Tests', () {
    test('passes through feature vector unchanged when lengths match', () {
      final input = List<double>.generate(63, (i) => i.toDouble());
      final adapted = TensorShapeAdapter.adapt(input, 63);

      expect(adapted.length, equals(63));
      expect(adapted, equals(input));
    });

    test('truncates excess features when vector is longer than target size', () {
      final input = List<double>.generate(80, (i) => (i + 1).toDouble());
      final adapted = TensorShapeAdapter.adapt(input, 50);

      expect(adapted.length, equals(50));
      expect(adapted.first, equals(1.0));
      expect(adapted.last, equals(50.0));
    });

    test('pads missing feature slots with default 0.0 when vector is shorter than target size', () {
      final input = List<double>.generate(50, (i) => 1.0);
      final adapted = TensorShapeAdapter.adapt(input, 80);

      expect(adapted.length, equals(80));
      expect(adapted.take(50).every((v) => v == 1.0), isTrue);
      expect(adapted.skip(50).every((v) => v == 0.0), isTrue);
    });

    test('pads missing slots with custom padding value when specified', () {
      final input = [1.0, 2.0, 3.0];
      final adapted = TensorShapeAdapter.adapt(input, 5, paddingValue: -1.0);

      expect(adapted, equals([1.0, 2.0, 3.0, -1.0, -1.0]));
    });

    test('adaptVector accepts FeatureVector and returns adapted FeatureVector', () {
      final fv = FeatureVector(List<double>.filled(63, 2.5));
      final adaptedFv = TensorShapeAdapter.adaptVector(fv, 80, paddingValue: 0.0);

      expect(adaptedFv.length, equals(80));
      expect(adaptedFv.values.take(63).every((v) => v == 2.5), isTrue);
      expect(adaptedFv.values.skip(63).every((v) => v == 0.0), isTrue);
    });

    test('throws ArgumentError on invalid target length <= 0', () {
      expect(() => TensorShapeAdapter.adapt([1.0, 2.0], 0), throwsArgumentError);
      expect(() => TensorShapeAdapter.adapt([1.0, 2.0], -5), throwsArgumentError);
    });
  });
}
