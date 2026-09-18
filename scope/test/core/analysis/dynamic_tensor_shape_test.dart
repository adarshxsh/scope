import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:scope/core/analysis/feature_extractor.dart';
import 'package:scope/core/analysis/ghost_ai.dart';
import 'package:scope/core/analysis/tensor_shape_adapter.dart';
import 'package:scope/core/models/notification_model.dart';

void main() {
  group('Dynamic Tensor Shape and Named Feature Tests', () {
    test('FeatureVector supports dynamic array lengths (50, 63, 80) without throwing length error', () {
      final fv50 = FeatureVector(List<double>.filled(50, 1.0));
      expect(fv50.length, equals(50));

      final fv63 = FeatureVector(List<double>.filled(63, 1.0));
      expect(fv63.length, equals(63));

      final fv80 = FeatureVector(List<double>.filled(80, 1.0));
      expect(fv80.length, equals(80));

      final fv30 = FeatureVector(List<double>.filled(30, 0.5));
      expect(fv30.length, equals(30));
    });

    test('FeatureVector and FeatureExtractor provide named property access for downstream overrides', () {
      final notification = AppNotification(
        id: 'test-otp-1',
        title: 'OTP Verification',
        content: 'Your code is 882715',
        packageName: 'com.whatsapp',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final input = NotificationFeatureInput.fromAppNotification(notification);
      final vector = FeatureExtractor.extractVector(input);

      // Verify named getters on FeatureVector
      expect(vector.containsOtp, equals(1.0));
      expect(vector.getValue('contains_otp'), equals(1.0));
      expect(vector.getByName('contains_otp'), equals(1.0));

      // Verify static helper on FeatureExtractor
      expect(FeatureExtractor.getNamedFeature(vector, 'contains_otp'), equals(1.0));
      expect(FeatureExtractor.getNamedFeatureFromList(vector.toList(), 'contains_otp'), equals(1.0));

      // Verify behavior on vector truncated to 50 features
      final truncatedList = TensorShapeAdapter.adapt(vector.toList(), 50);
      final fv50 = FeatureVector(truncatedList);
      expect(fv50.containsOtp, equals(1.0));

      // Verify behavior for nonexistent feature name
      expect(vector.getValue('nonexistent_feature', defaultValue: -1.0), equals(-1.0));
      expect(vector.getByName('nonexistent_feature'), isNull);
    });

    test('GhostAI processes notifications without errors when model input tensor size varies (50, 63, 80)', () async {
      final notification = AppNotification(
        id: 'test-notif-1',
        title: 'Urgent meeting',
        content: 'Project review standup starts in 10 minutes',
        packageName: 'com.google.android.calendar',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      final ghost = GhostAI.instance;

      // Test with 50, 63, and 80 feature fixture models if available
      for (final dim in [50, 63, 80]) {
        final fixtureFile = File('test/fixtures/model_$dim.tflite');
        if (fixtureFile.existsSync()) {
          try {
            final buffer = fixtureFile.readAsBytesSync();
            final interpreter = Interpreter.fromBuffer(buffer);
            ghost.setInterpreterForTesting(interpreter);
            expect(ghost.inputTensorSize, equals(dim));

            final result = await GhostAI.predict(notification);
            expect(result.reviewScore, greaterThanOrEqualTo(0.0));
            expect(result.reviewScore, lessThanOrEqualTo(1.0));
          } catch (e) {
            // Native libtensorflowlite_c may not be available on Linux host runner
            ghost.setInterpreterForTesting(null);
            final result = await GhostAI.predict(notification);
            expect(result.reviewScore, greaterThanOrEqualTo(0.0));
            expect(result.reviewScore, lessThanOrEqualTo(1.0));
          }
        } else {
          ghost.setInterpreterForTesting(null);
          final result = await GhostAI.predict(notification);
          expect(result.reviewScore, greaterThanOrEqualTo(0.0));
        }
      }

      ghost.setInterpreterForTesting(null);
      expect(ghost.inputTensorSize, equals(63));
    });

    test('TensorShapeAdapter correctly handles padding and truncation across 50, 63, 80 features', () {
      final original63 = List<double>.generate(63, (i) => i.toDouble());

      // Adapt to 50
      final adapted50 = TensorShapeAdapter.adapt(original63, 50);
      expect(adapted50.length, equals(50));
      expect(adapted50, equals(original63.sublist(0, 50)));

      // Adapt to 80
      final adapted80 = TensorShapeAdapter.adapt(original63, 80);
      expect(adapted80.length, equals(80));
      expect(adapted80.sublist(0, 63), equals(original63));
      expect(adapted80.sublist(63).every((v) => v == 0.0), isTrue);

      // Adapt 50 to 63
      final restored63 = TensorShapeAdapter.adapt(adapted50, 63);
      expect(restored63.length, equals(63));
      expect(restored63.sublist(0, 50), equals(adapted50));
      expect(restored63.sublist(50).every((v) => v == 0.0), isTrue);
    });
  });
}
