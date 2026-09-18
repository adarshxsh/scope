"""Unit tests for MLP model architecture and z-score clipping."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.export.tflite_exporter import export_float32_tflite, export_saved_model
from training.models.mlp import build_baseline_mlp


class TestMLPZScoreClipping(unittest.TestCase):
    def setUp(self):
        self.mean = [10.0] * FEATURE_VECTOR_SIZE
        self.stddev = [2.0] * FEATURE_VECTOR_SIZE
        self.model = build_baseline_mlp(
            mean=self.mean,
            stddev=self.stddev,
            learning_rate=0.001,
        )

    def test_model_layer_structure(self):
        """Verify clip_zscore layer exists in model."""
        layer_names = [layer.name for layer in self.model.layers]
        self.assertIn("clip_zscore", layer_names)

    def test_zscore_clamping_bounds(self):
        """Verify feature activations immediately after normalization are clamped to [-5.0, 5.0]."""
        sub_model = tf.keras.Model(
            inputs=self.model.input,
            outputs=self.model.get_layer("clip_zscore").output,
        )

        # Input vector with extreme values:
        # -1000.0 => z-score = (-1000 - 10) / 2 = -505.0 => clipped to -5.0
        # +1000.0 => z-score = (+1000 - 10) / 2 = +495.0 => clipped to +5.0
        # 20.0 => z-score = (20 - 10) / 2 = 5.0 => exactly 5.0
        extreme_inputs = np.array(
            [
                [-1000.0] * FEATURE_VECTOR_SIZE,
                [1000.0] * FEATURE_VECTOR_SIZE,
                [100000.0] * FEATURE_VECTOR_SIZE,  # Extreme content length / monetary amount
                [20.0] * FEATURE_VECTOR_SIZE,
            ],
            dtype=np.float32,
        )

        clipped_features = sub_model.predict(extreme_inputs)

        self.assertTrue(np.all(clipped_features >= -5.0))
        self.assertTrue(np.all(clipped_features <= 5.0))
        self.assertFalse(np.isnan(clipped_features).any())

        # Check exact clamping value for extreme positive input vs +5 stddev input (val=20.0)
        np.testing.assert_allclose(clipped_features[1], 5.0, atol=1e-5)
        np.testing.assert_allclose(clipped_features[2], 5.0, atol=1e-5)
        np.testing.assert_allclose(clipped_features[3], 5.0, atol=1e-5)
        # Extreme negative input should be clamped to -5.0
        np.testing.assert_allclose(clipped_features[0], -5.0, atol=1e-5)

    def test_inference_stability_and_tflite_export(self):
        """Verify SavedModel and TFLite FlatBuffer execution with outlier inputs."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            saved_model_dir = export_saved_model(self.model, tmp_path / "saved_model")
            tflite_path = export_float32_tflite(saved_model_dir, tmp_path / "ghost_ai.tflite")

            self.assertTrue(tflite_path.exists())

            interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
            interpreter.allocate_tensors()

            input_details = interpreter.get_input_details()
            output_details = interpreter.get_output_details()

            outlier_input = np.ones((1, FEATURE_VECTOR_SIZE), dtype=np.float32) * 100000.0
            interpreter.set_tensor(input_details[0]["index"], outlier_input)
            interpreter.invoke()
            pred_outlier = interpreter.get_tensor(output_details[0]["index"])[0][0]

            self.assertFalse(np.isnan(pred_outlier))
            self.assertFalse(np.isinf(pred_outlier))

            # Compare with boundary input (20.0 => exactly +5.0 stddev)
            boundary_input = np.ones((1, FEATURE_VECTOR_SIZE), dtype=np.float32) * 20.0
            interpreter.set_tensor(input_details[0]["index"], boundary_input)
            interpreter.invoke()
            pred_boundary = interpreter.get_tensor(output_details[0]["index"])[0][0]

            np.testing.assert_allclose(pred_outlier, pred_boundary, rtol=1e-5)


if __name__ == "__main__":
    unittest.main()
