"""Unit tests for AttentionOS MLP model building, preprocessing, and TFLite export."""

import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""

import unittest
import numpy as np
import tensorflow as tf

tf.config.set_visible_devices([], 'GPU')

from training.config import CONTINUOUS_FEATURE_INDICES, FEATURE_VECTOR_SIZE
from training.models.mlp import build_baseline_mlp
from training.utils.feature_extractor import apply_log1p_transform, extract_features


class TestMLPPipeline(unittest.TestCase):

    def setUp(self):
        self.mean = [0.0] * FEATURE_VECTOR_SIZE
        self.stddev = [1.0] * FEATURE_VECTOR_SIZE
        self.learning_rate = 1e-3

    def test_build_baseline_mlp(self):
        """Criterion 1: build_baseline_mlp includes tf.clip_by_value(x, -5.0, 5.0) and builds cleanly."""
        model = build_baseline_mlp(self.mean, self.stddev, self.learning_rate)
        self.assertIsNotNone(model)
        
        # Verify layer names
        layer_names = [layer.name for layer in model.layers]
        self.assertIn("log1p_transform", layer_names)
        self.assertIn("normalization", layer_names)
        self.assertIn("zscore_clipping", layer_names)

        # Test forward pass with dummy batch
        dummy_input = np.random.randn(2, FEATURE_VECTOR_SIZE).astype(np.float32)
        output = model.predict(dummy_input, verbose=0)
        self.assertEqual(output.shape, (2, 1))

    def test_log1p_transform_handling_and_negative_inputs(self):
        """Criterion 2 & Constraint: np.log1p(np.maximum(0.0, x)) handles positive and negative continuous values."""
        raw_vector = np.zeros(FEATURE_VECTOR_SIZE, dtype=np.float32)
        raw_vector[0] = 100.0  # title_length
        raw_vector[1] = 50000.0  # body_length
        raw_vector[49] = -1.0  # missing deadline (negative value)
        raw_vector[50] = 100000000.0  # amount

        transformed = apply_log1p_transform(raw_vector)

        # Continuous features should be transformed
        self.assertAlmostEqual(transformed[0], np.log1p(100.0), places=5)
        self.assertAlmostEqual(transformed[1], np.log1p(50000.0), places=5)
        # Negative deadline duration must be non-negative clamped before log1p -> log1p(0) = 0
        self.assertAlmostEqual(transformed[49], 0.0, places=5)
        self.assertAlmostEqual(transformed[50], np.log1p(100000000.0), places=5)

        # Non-continuous features remain unchanged
        self.assertEqual(transformed[3], 0.0)

    def test_tflite_export_and_outlier_prediction(self):
        """Criterion 3 & Criterion 4: TFLite model exports valid flatbuffer and outlier inputs yield score < 1.0."""
        model = build_baseline_mlp(self.mean, self.stddev, self.learning_rate)
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        tflite_bytes = converter.convert()
        self.assertGreater(len(tflite_bytes), 0)

        # Load TFLite interpreter and run outlier test
        interpreter = tf.lite.Interpreter(model_content=tflite_bytes)
        interpreter.allocate_tensors()

        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()

        outlier_vector = np.zeros((1, FEATURE_VECTOR_SIZE), dtype=np.float32)
        outlier_vector[0, 1] = 50000.0  # x_body_length = 50,000
        outlier_vector[0, 50] = 100000000.0  # x_amount = 100,000,000.0

        interpreter.set_tensor(input_details[0]["index"], outlier_vector)
        interpreter.invoke()
        raw_output = interpreter.get_tensor(output_details[0]["index"])[0][0]

        # GhostAI._predict calculates: (raw_output / 100.0).clamp(0.0, 1.0)
        score = max(0.0, min(1.0, float(raw_output) / 100.0))
        self.assertLess(score, 1.0, f"Expected non-saturated score < 1.0, got {score}")

    def test_extract_features_apply_log1p(self):
        """Requirement 1: extract_features transforms continuous features when apply_log1p=True."""
        sample_record = {
            "title": "Bank Alert",
            "body": "Your account credited with Rs. 50000.",
            "package_name": "com.bank.app",
        }
        features_raw = extract_features(sample_record, apply_log1p=False)
        features_log1p = extract_features(sample_record, apply_log1p=True)

        self.assertEqual(len(features_raw), FEATURE_VECTOR_SIZE)
        self.assertEqual(len(features_log1p), FEATURE_VECTOR_SIZE)

        # Amount at index 50
        raw_amount = features_raw[50]
        log1p_amount = features_log1p[50]
        self.assertGreater(raw_amount, 0.0)
        self.assertAlmostEqual(log1p_amount, np.log1p(raw_amount), places=5)


if __name__ == "__main__":
    unittest.main()
