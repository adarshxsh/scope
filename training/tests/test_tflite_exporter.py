"""Unit tests for SavedModel export and TFLite quantization pipeline."""

import tempfile
import unittest
from pathlib import Path

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.export.tflite_exporter import (
    export_dynamic_range_tflite,
    export_float32_tflite,
    export_quantized_tflite,
    export_saved_model,
)
from training.models.mlp import build_baseline_mlp


class TestTFLiteExporter(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.export_dir = Path(self.temp_dir.name)

        mean_val = np.zeros(FEATURE_VECTOR_SIZE)
        stddev_val = np.ones(FEATURE_VECTOR_SIZE)
        self.model = build_baseline_mlp(
            mean=mean_val.tolist(),
            stddev=stddev_val.tolist(),
            learning_rate=0.001,
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_export_saved_model_binds_input_signature(self) -> None:
        saved_model_dir = self.export_dir / "saved_model"
        export_saved_model(self.model, saved_model_dir)

        self.assertTrue(saved_model_dir.exists())
        loaded = tf.saved_model.load(str(saved_model_dir))
        self.assertIn("serving_default", loaded.signatures)
        serving_fn = loaded.signatures["serving_default"]
        input_spec = serving_fn.structured_input_signature[1]
        input_tensor_spec = list(input_spec.values())[0]
        self.assertEqual(input_tensor_spec.shape.as_list(), [None, FEATURE_VECTOR_SIZE])
        self.assertEqual(input_tensor_spec.dtype, tf.float32)

    def test_export_quantized_tflite_creates_valid_model(self) -> None:
        saved_model_dir = self.export_dir / "saved_model"
        export_saved_model(self.model, saved_model_dir)

        quantized_path = self.export_dir / "quantized.tflite"
        dummy_features = np.random.randn(100, FEATURE_VECTOR_SIZE).astype(np.float32)
        export_quantized_tflite(saved_model_dir, quantized_path, representative_data=dummy_features)

        self.assertTrue(quantized_path.exists())
        quantized_size = quantized_path.stat().st_size
        self.assertGreater(quantized_size, 0)

        interpreter = tf.lite.Interpreter(model_path=str(quantized_path))
        interpreter.allocate_tensors()
        input_details = interpreter.get_input_details()

        self.assertEqual(input_details[0]["shape"].tolist(), [1, FEATURE_VECTOR_SIZE])
        self.assertEqual(input_details[0]["dtype"], np.float32)

    def test_export_dynamic_range_tflite(self) -> None:
        saved_model_dir = self.export_dir / "saved_model"
        export_saved_model(self.model, saved_model_dir)

        dynamic_path = self.export_dir / "dynamic.tflite"
        export_dynamic_range_tflite(saved_model_dir, dynamic_path)

        self.assertTrue(dynamic_path.exists())
        self.assertGreater(dynamic_path.stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
