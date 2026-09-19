"""Unit tests for continuous metric upper-bound clamping and in-graph z-score clipping."""

import unittest
import numpy as np
import tensorflow as tf

from training.utils.feature_extractor import extract_features, extract_amount
from training.models.mlp import build_baseline_mlp


class TestInGraphClipping(unittest.TestCase):

    def test_python_feature_extractor_clamping(self) -> None:
        # Outlier notification record with extreme lengths, word count, amount, and deadline
        extreme_record = {
            "title": "A" * 12000,
            "body": "word " * 15000,
            "packageName": "com.example.outlier",
            "android": {
                "importance": 3,
            },
            "timestamp": "2026-06-24T10:00:00+00:00",
        }

        features = extract_features(extreme_record)

        title_length = features[0]
        body_length = features[1]
        word_count = features[2]

        self.assertLessEqual(title_length, 500.0)
        self.assertLessEqual(body_length, 5000.0)
        self.assertLessEqual(word_count, 1000.0)

    def test_python_amount_clamping(self) -> None:
        amount = extract_amount("Payment of $5,000,000 processed.")
        self.assertIsNotNone(amount)
        self.assertEqual(amount, 1000000.0)

    def test_in_graph_zscore_clipping(self) -> None:
        mean = [0.0] * 63
        stddev = [1.0] * 63
        model = build_baseline_mlp(mean, stddev, learning_rate=0.001)

        # Check if zscore_clipping layer exists
        layer_names = [layer.name for layer in model.layers]
        self.assertIn("zscore_clipping", layer_names)

        # Create intermediate model up to zscore_clipping layer
        clipping_layer = model.get_layer("zscore_clipping")
        sub_model = tf.keras.Model(inputs=model.input, outputs=clipping_layer.output)

        # Pass extreme input features (e.g. 100000.0)
        extreme_inputs = np.full((1, 63), 100000.0, dtype=np.float32)
        clipped_outputs = sub_model.predict(extreme_inputs)

        # Assert all clipped values are within [-5.0, 5.0]
        self.assertTrue(np.all(clipped_outputs >= -5.0))
        self.assertTrue(np.all(clipped_outputs <= 5.0))


if __name__ == "__main__":
    unittest.main()
