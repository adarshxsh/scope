"""Tests for TFLite exporter and quantization pipeline."""

import unittest
from pathlib import Path
import numpy as np
import tensorflow as tf

from training.export.tflite_exporter import (
    export_saved_model,
    export_float32_tflite,
    export_dynamic_range_tflite,
    export_quantized_tflite,
)


class TestTFLiteExporter(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = Path("/tmp/test_exporter_run")
        self.tmp_dir.mkdir(parents=True, exist_ok=True)

        inputs = tf.keras.Input(shape=(63,))
        outputs = tf.keras.layers.Dense(1)(inputs)
        self.model = tf.keras.Model(inputs=inputs, outputs=outputs)
        self.saved_model_dir = export_saved_model(
            self.model, self.tmp_dir / "saved_model"
        )

    def test_export_float32(self):
        output_path = self.tmp_dir / "float32.tflite"
        res = export_float32_tflite(self.saved_model_dir, output_path)
        self.assertTrue(res.exists())
        self.assertGreater(res.stat().st_size, 0)

    def test_export_dynamic_range(self):
        output_path = self.tmp_dir / "dynamic.tflite"
        res = export_dynamic_range_tflite(self.saved_model_dir, output_path)
        self.assertTrue(res.exists())
        self.assertGreater(res.stat().st_size, 0)

    def test_export_integer_quantized_with_representative_data(self):
        output_path = self.tmp_dir / "quantized.tflite"
        dummy_features = np.random.randn(100, 63).astype(np.float32)
        res = export_quantized_tflite(
            self.saved_model_dir,
            output_path,
            representative_data=dummy_features,
        )
        self.assertTrue(res.exists())
        self.assertGreater(res.stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
