"""Unit tests for TFLite model export, quantization, and shape validation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.export.tflite_exporter import (
    export_float32_tflite,
    export_quantized_tflite,
    export_saved_model,
    validate_tflite_export,
)
from training.models.mlp import build_baseline_mlp


class TestTFLiteExporter(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.temp_dir.name)

        # Build a lightweight dummy MLP model for testing
        mean = [0.0] * FEATURE_VECTOR_SIZE
        stddev = [1.0] * FEATURE_VECTOR_SIZE
        self.model = build_baseline_mlp(mean=mean, stddev=stddev, learning_rate=0.001)

        # Save model
        self.saved_model_dir = self.tmp_path / "saved_model"
        export_saved_model(self.model, self.saved_model_dir, input_shape=(1, FEATURE_VECTOR_SIZE))

        # Representative dataset sample
        np.random.seed(42)
        self.representative_data = np.random.randn(32, FEATURE_VECTOR_SIZE).astype(np.float32)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_export_saved_model_creates_directory(self) -> None:
        self.assertTrue(self.saved_model_dir.exists())
        self.assertTrue((self.saved_model_dir / "saved_model.pb").exists())

    def test_export_float32_tflite_creates_valid_model(self) -> None:
        float32_path = self.tmp_path / "model_float32.tflite"
        res_path = export_float32_tflite(
            self.saved_model_dir,
            float32_path,
            expected_input_shape=(1, FEATURE_VECTOR_SIZE),
        )
        self.assertEqual(res_path, float32_path)
        self.assertTrue(float32_path.exists())

        info = validate_tflite_export(float32_path, expected_input_shape=(1, FEATURE_VECTOR_SIZE))
        self.assertEqual(info["input_shape"], [1, FEATURE_VECTOR_SIZE])
        self.assertEqual(info["input_dtype"], "float32")
        self.assertGreater(info["file_size_bytes"], 0)

    def test_export_quantized_tflite_reduces_size_and_validates(self) -> None:
        float32_path = self.tmp_path / "model_float32.tflite"
        export_float32_tflite(
            self.saved_model_dir,
            float32_path,
            expected_input_shape=(1, FEATURE_VECTOR_SIZE),
        )

        quantized_path = self.tmp_path / "model_quantized.tflite"
        res_path = export_quantized_tflite(
            self.saved_model_dir,
            quantized_path,
            representative_data=self.representative_data,
            expected_input_shape=(1, FEATURE_VECTOR_SIZE),
        )
        self.assertEqual(res_path, quantized_path)
        self.assertTrue(quantized_path.exists())

        quant_info = validate_tflite_export(
            quantized_path, expected_input_shape=(1, FEATURE_VECTOR_SIZE)
        )
        self.assertEqual(quant_info["input_shape"], [1, FEATURE_VECTOR_SIZE])
        self.assertEqual(quant_info["input_dtype"], "float32")

        # Verify quantization reduced binary size by at least 30%
        float32_size = float32_path.stat().st_size
        quant_size = quantized_path.stat().st_size
        self.assertLess(quant_size, float32_size * 0.70)

    def test_validate_tflite_export_nonexistent_file_raises(self) -> None:
        missing_path = self.tmp_path / "does_not_exist.tflite"
        with self.assertRaises(FileNotFoundError):
            validate_tflite_export(missing_path)

    def test_validate_tflite_export_too_small_file_raises(self) -> None:
        corrupt_path = self.tmp_path / "tiny.tflite"
        corrupt_path.write_bytes(b"TFL3")
        with self.assertRaises(ValueError) as ctx:
            validate_tflite_export(corrupt_path)
        self.assertIn("too small", str(ctx.exception))

    def test_validate_tflite_export_invalid_magic_header_raises(self) -> None:
        corrupt_path = self.tmp_path / "bad_header.tflite"
        corrupt_path.write_bytes(b"\x00\x00\x00\x00BADH\x00\x00\x00\x00")
        with self.assertRaises(ValueError) as ctx:
            validate_tflite_export(corrupt_path)
        self.assertIn("magic header", str(ctx.exception))

    def test_validate_tflite_export_shape_mismatch_raises(self) -> None:
        float32_path = self.tmp_path / "model_float32.tflite"
        export_float32_tflite(self.saved_model_dir, float32_path)

        with self.assertRaises(ValueError) as ctx:
            validate_tflite_export(float32_path, expected_input_shape=(1, 10))
        self.assertIn("Input shape dimension mismatch", str(ctx.exception))

    def test_validate_tflite_export_rank_mismatch_raises(self) -> None:
        float32_path = self.tmp_path / "model_float32.tflite"
        export_float32_tflite(self.saved_model_dir, float32_path)

        with self.assertRaises(ValueError) as ctx:
            validate_tflite_export(float32_path, expected_input_shape=(1, FEATURE_VECTOR_SIZE, 1))
        self.assertIn("Input rank mismatch", str(ctx.exception))

    def test_validate_tflite_export_dtype_mismatch_raises(self) -> None:
        float32_path = self.tmp_path / "model_float32.tflite"
        export_float32_tflite(self.saved_model_dir, float32_path)

        with self.assertRaises(TypeError) as ctx:
            validate_tflite_export(float32_path, expected_dtype=np.int32)
        self.assertIn("Input dtype mismatch", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
