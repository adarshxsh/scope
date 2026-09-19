import json
import tempfile
import unittest
from pathlib import Path
import numpy as np
import tensorflow as tf

from training.models.mlp import build_baseline_mlp
from training.export.tflite_exporter import export_saved_model, export_float32_tflite
from training.utils.feature_extractor import extract_features


class TestDynamicVectorMetadata(unittest.TestCase):
    def test_extract_features_padding(self):
        record = {
            "title": "Security Alert",
            "body": "Your OTP is 123456",
            "package_name": "com.scope.app",
        }
        feat63 = extract_features(record)
        self.assertEqual(len(feat63), 63)

        feat128 = extract_features(record, target_dimension=128)
        self.assertEqual(len(feat128), 128)
        self.assertEqual(feat128[:63], feat63)
        self.assertEqual(feat128[63:], [0.0] * 65)

        feat256 = extract_features(record, target_dimension=256)
        self.assertEqual(len(feat256), 256)
        self.assertEqual(feat256[:63], feat63)
        self.assertEqual(feat256[63:], [0.0] * 193)

    def test_mlp_model_shapes_and_export_metadata(self):
        for dim in (128, 256):
            with tempfile.TemporaryDirectory() as tmp_dir:
                tmp_path = Path(tmp_dir)
                mean = [0.0] * dim
                stddev = [1.0] * dim

                model = build_baseline_mlp(
                    mean=mean,
                    stddev=stddev,
                    learning_rate=1e-3,
                    feature_vector_size=dim,
                )
                self.assertEqual(model.input_shape, (None, dim))

                # Test forward pass with dummy input
                dummy_input = np.zeros((1, dim), dtype=np.float32)
                output = model.predict(dummy_input, verbose=0)
                self.assertEqual(output.shape, (1, 1))

                # Test SavedModel and TFLite Export with Metadata JSON headers
                saved_model_dir = export_saved_model(model, tmp_path / "saved_model")
                metadata = {
                    "feature_vector_size": dim,
                    "input_vector_dimension": dim,
                    "flutter": {
                        "input_shape": [1, dim],
                        "input_vector_dimension": dim,
                        "output_shape": [1, 1],
                    },
                }

                tflite_path = export_float32_tflite(
                    saved_model_dir,
                    tmp_path / "model.tflite",
                    metadata=metadata,
                )
                self.assertTrue(tflite_path.exists())

                # Check metadata JSON header file
                meta_json_path = tmp_path / "metadata.json"
                self.assertTrue(meta_json_path.exists())
                meta_data = json.loads(meta_json_path.read_text(encoding="utf-8"))
                self.assertEqual(meta_data["feature_vector_size"], dim)
                self.assertEqual(meta_data["flutter"]["input_shape"], [1, dim])


if __name__ == "__main__":
    unittest.main()
