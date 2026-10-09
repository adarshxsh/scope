import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from training.export.tflite_exporter import generate_model_manifest


class TestTfLiteExporter(unittest.TestCase):
    def test_generate_model_manifest_creates_valid_json(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            tflite_file = temp_path / "model.tflite"
            sample_bytes = b"dummy tflite model content"
            tflite_file.write_bytes(sample_bytes)

            manifest_path = generate_model_manifest(
                tflite_path=tflite_file,
                version="1.0.0",
                input_shapes=[[1, 63]],
                output_shapes=[[1, 1]],
                target_engine="GhostAI",
            )

            self.assertTrue(manifest_path.exists())
            manifest_content = json.loads(manifest_path.read_text())

            expected_sha256 = hashlib.sha256(sample_bytes).hexdigest()
            self.assertEqual(manifest_content["version"], "1.0.0")
            self.assertEqual(manifest_content["sha256"], expected_sha256)
            self.assertEqual(manifest_content["checksum"], expected_sha256)
            self.assertEqual(manifest_content["input_tensor_shapes"], [[1, 63]])
            self.assertEqual(manifest_content["output_tensor_shapes"], [[1, 1]])
            self.assertEqual(manifest_content["target_engine"], "GhostAI")


if __name__ == "__main__":
    unittest.main()
