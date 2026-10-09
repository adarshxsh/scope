import unittest
import tempfile
from pathlib import Path

import tensorflow as tf
from training.export.tflite_exporter import (
    export_float32_tflite,
    export_quantized_tflite,
    export_saved_model,
    validate_tflite_interpreter_shapes,
)


class TestTFLiteExporter(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.temp_dir.name)

        # Create a mock model matching Ghost AI architecture: input shape (63,), output shape (1,)
        inputs = tf.keras.Input(shape=(63,), name="input_layer")
        x = tf.keras.layers.Dense(128, activation="relu")(inputs)
        x = tf.keras.layers.Dense(64, activation="relu")(x)
        outputs = tf.keras.layers.Dense(1, activation="linear", name="output_layer")(x)
        self.model = tf.keras.Model(inputs=inputs, outputs=outputs)

        self.saved_model_dir = export_saved_model(self.model, self.tmp_path / "saved_model")

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_export_quantized_tflite_creates_file(self):
        output_file = self.tmp_path / "model_quant.tflite"
        res_path = export_quantized_tflite(self.saved_model_dir, output_file)

        self.assertTrue(res_path.exists())
        self.assertGreater(res_path.stat().st_size, 0)

    def test_quantization_size_reduction(self):
        float32_file = self.tmp_path / "model_float32.tflite"
        quantized_file = self.tmp_path / "model_quant.tflite"

        export_float32_tflite(self.saved_model_dir, float32_file)
        export_quantized_tflite(self.saved_model_dir, quantized_file)

        float32_size = float32_file.stat().st_size
        quantized_size = quantized_file.stat().st_size

        self.assertLess(quantized_size, float32_size)

    def test_validate_tflite_interpreter_shapes_valid(self):
        converter = tf.lite.TFLiteConverter.from_saved_model(str(self.saved_model_dir))
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        model_bytes = converter.convert()

        # Should not raise exception
        validate_tflite_interpreter_shapes(
            model_bytes,
            expected_input_shape=(1, 63),
            expected_output_shape=(1, 1),
        )

    def test_validate_tflite_interpreter_shapes_invalid_input(self):
        converter = tf.lite.TFLiteConverter.from_saved_model(str(self.saved_model_dir))
        model_bytes = converter.convert()

        with self.assertRaises(ValueError) as ctx:
            validate_tflite_interpreter_shapes(
                model_bytes,
                expected_input_shape=(1, 32),
                expected_output_shape=(1, 1),
            )
        self.assertIn("TFLite input tensor shape mismatch", str(ctx.exception))

    def test_validate_tflite_interpreter_shapes_invalid_output(self):
        converter = tf.lite.TFLiteConverter.from_saved_model(str(self.saved_model_dir))
        model_bytes = converter.convert()

        with self.assertRaises(ValueError) as ctx:
            validate_tflite_interpreter_shapes(
                model_bytes,
                expected_input_shape=(1, 63),
                expected_output_shape=(1, 5),
            )
        self.assertIn("TFLite output tensor shape mismatch", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
