"""Unit tests for calibrated INT8 post-training quantization and model validation."""

from __future__ import annotations

import os
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["TF_METAL_DEVICE_THREAD_LIMIT"] = "1"

import tempfile
import unittest
from pathlib import Path

import numpy as np
import tensorflow as tf

tf.config.set_visible_devices([], "GPU")

from training.config import FEATURE_VECTOR_SIZE
from training.export.tflite_exporter import (
    _representative_dataset,
    export_float32_tflite,
    export_int8_tflite,
    export_saved_model,
)
from training.models.mlp import build_baseline_mlp
from training.utils.validate_model import evaluate_tflite_model


class TestInt8Quantization(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.temp_dir.name)

        # Build simple model with 63 features
        mean_val = [0.0] * FEATURE_VECTOR_SIZE
        stddev_val = [1.0] * FEATURE_VECTOR_SIZE
        self.model = build_baseline_mlp(mean=mean_val, stddev=stddev_val, learning_rate=1e-3)

        # Generate synthetic training features
        np.random.seed(42)
        self.x_train = np.random.randn(200, FEATURE_VECTOR_SIZE).astype(np.float32)
        self.y_train = np.random.uniform(0.0, 100.0, size=(200, 1)).astype(np.float32)

        # Export SavedModel
        self.saved_model_dir = export_saved_model(self.model, self.tmp_path / "saved_model")

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_representative_dataset_generator(self) -> None:
        gen = _representative_dataset(self.x_train, max_samples=10)
        samples = list(gen())
        self.assertEqual(len(samples), 10)
        self.assertEqual(samples[0][0].shape, (1, FEATURE_VECTOR_SIZE))
        self.assertEqual(samples[0][0].dtype, np.float32)

    def test_export_int8_tflite_size_reduction(self) -> None:
        float32_path = export_float32_tflite(
            self.saved_model_dir, self.tmp_path / "ghost_ai_float32.tflite"
        )
        int8_path = export_int8_tflite(
            self.saved_model_dir, self.tmp_path / "ghost_ai.tflite", self.x_train
        )

        self.assertTrue(float32_path.exists())
        self.assertTrue(int8_path.exists())

        float32_size = float32_path.stat().st_size
        int8_size = int8_path.stat().st_size

        self.assertGreater(float32_size, 0)
        self.assertGreater(int8_size, 0)

        size_reduction = (1.0 - (int8_size / float32_size)) * 100.0
        # Check size reduction is at least 60%
        self.assertGreaterEqual(
            size_reduction,
            60.0,
            f"Int8 size reduction expected >=60%, got {size_reduction:.2f}% ({float32_size} -> {int8_size} bytes)",
        )

    def test_tensor_shape_signatures_and_contracts(self) -> None:
        int8_path = export_int8_tflite(
            self.saved_model_dir, self.tmp_path / "ghost_ai.tflite", self.x_train
        )

        interpreter = tf.lite.Interpreter(model_path=str(int8_path))
        interpreter.allocate_tensors()

        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()

        self.assertEqual(len(input_details), 1)
        self.assertEqual(len(output_details), 1)

        input_shape = list(input_details[0]["shape"])
        output_shape = list(output_details[0]["shape"])

        # Check expected [1, 63] input and [1, 1] output contracts
        self.assertEqual(input_shape, [1, FEATURE_VECTOR_SIZE])
        self.assertEqual(output_shape, [1, 1])

    def test_evaluate_tflite_model_metrics(self) -> None:
        int8_path = export_int8_tflite(
            self.saved_model_dir, self.tmp_path / "ghost_ai.tflite", self.x_train
        )

        eval_results = evaluate_tflite_model(int8_path, self.x_train, self.y_train.flatten())

        self.assertIn("mae", eval_results)
        self.assertIn("rmse", eval_results)
        self.assertIn("r2", eval_results)
        self.assertIn("avg_latency_ms", eval_results)
        self.assertIn("p95_latency_ms", eval_results)
        self.assertIn("size_bytes", eval_results)

        self.assertGreaterEqual(eval_results["mae"], 0.0)
        self.assertGreater(eval_results["avg_latency_ms"], 0.0)
        self.assertEqual(eval_results["input_shape"], [1, FEATURE_VECTOR_SIZE])
        self.assertEqual(eval_results["output_shape"], [1, 1])


if __name__ == "__main__":
    unittest.main()
