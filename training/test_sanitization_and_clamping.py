"""Unit tests for feature range sanitization and z-score clipping."""

from __future__ import annotations

import unittest
import numpy as np
import tensorflow as tf

from training.models.mlp import build_baseline_mlp
from training.utils.feature_extractor import (
    MAX_AMOUNT,
    MAX_BODY_LENGTH,
    MAX_DEADLINE_MINUTES,
    MAX_TITLE_LENGTH,
    MAX_WORD_COUNT,
    extract_features,
    extract_features_from_dict,
)


class TestFeatureSanitizationAndClamping(unittest.TestCase):
    def test_python_feature_extractor_clamping(self):
        huge_record = {
            "title": "A" * 2000,
            "body": ("B " * 2000) + " paid $5,000,000 in 9999 days",
            "package_name": "com.example.outlier",
            "timestamp": "2026-06-26T12:00:00+00:00",
        }

        features = extract_features(huge_record)
        features_alias = extract_features_from_dict(huge_record)

        self.assertEqual(features, features_alias)
        self.assertEqual(features[0], MAX_TITLE_LENGTH)
        self.assertEqual(features[1], MAX_BODY_LENGTH)
        self.assertEqual(features[2], MAX_WORD_COUNT)
        self.assertEqual(features[49], MAX_DEADLINE_MINUTES)
        self.assertEqual(features[50], MAX_AMOUNT)

    def test_mlp_model_zscore_clamping(self):
        mean = [0.0] * 63
        stddev = [1.0] * 63
        model = build_baseline_mlp(mean, stddev, learning_rate=0.001)

        layer_names = [layer.name for layer in model.layers]
        self.assertIn("zscore_clamping", layer_names)

        # Test extreme outlier inputs through MLP graph
        outlier_input = np.ones((1, 63), dtype=np.float32) * 100000.0
        output = model(outlier_input)

        self.assertFalse(np.isnan(output.numpy()).any())
        self.assertFalse(np.isinf(output.numpy()).any())


if __name__ == "__main__":
    unittest.main()
