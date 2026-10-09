"""Tests for dynamic feature vector dimensions."""

from __future__ import annotations

import unittest
import numpy as np

from training.dataset.loader import validate_feature_vector
from training.utils.preprocessing import _validate_features
from training.models.mlp import build_baseline_mlp
from training.dataset.schema import FEATURE_VECTOR_SIZE, FEATURE_NAMES


class TestDynamicDimensions(unittest.TestCase):
    def test_schema_feature_vector_size(self):
        self.assertEqual(FEATURE_VECTOR_SIZE, len(FEATURE_NAMES))

    def test_validate_feature_vector_custom_length(self):
        # Default behavior allows arbitrary length when expected_size is None
        vector10 = validate_feature_vector([1.0] * 10, "sample1")
        self.assertEqual(len(vector10), 10)

        # Enforces expected_size if specified
        with self.assertRaises(ValueError):
            validate_feature_vector([1.0] * 10, "sample1", expected_size=20)

        valid20 = validate_feature_vector([2.0] * 20, "sample2", expected_size=20)
        self.assertEqual(len(valid20), 20)

    def test_validate_features_custom_length(self):
        vector50 = _validate_features([0.5] * 50, "sample50")
        self.assertEqual(len(vector50), 50)

        with self.assertRaises(ValueError):
            _validate_features([0.5] * 50, "sample50", expected_size=63)

    def test_build_mlp_with_custom_dimensions(self):
        for feature_dim in [10, 50, 80]:
            mean = [0.0] * feature_dim
            stddev = [1.0] * feature_dim
            model = build_baseline_mlp(mean, stddev, learning_rate=1e-3, feature_dim=feature_dim)
            self.assertEqual(model.input_shape, (None, feature_dim))

            dummy_input = np.ones((2, feature_dim), dtype=np.float32)
            output = model(dummy_input)
            self.assertEqual(output.shape, (2, 1))


if __name__ == "__main__":
    unittest.main()
