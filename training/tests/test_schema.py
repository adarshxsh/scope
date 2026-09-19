"""Tests for Python training schema and configuration."""

import unittest
from training.dataset.schema import FEATURE_NAMES, FEATURE_VECTOR_SIZE
from training.config import FEATURE_VECTOR_SIZE as CONFIG_FEATURE_VECTOR_SIZE
from training.dataset.loader import validate_feature_vector


class TestSchemaAndConfig(unittest.TestCase):

    def test_feature_vector_size_derivation(self):
        self.assertEqual(FEATURE_VECTOR_SIZE, len(FEATURE_NAMES))
        self.assertEqual(CONFIG_FEATURE_VECTOR_SIZE, len(FEATURE_NAMES))

    def test_validate_feature_vector_valid(self):
        sample_features = [0.0] * FEATURE_VECTOR_SIZE
        result = validate_feature_vector(sample_features, "test_sample")
        self.assertEqual(len(result), FEATURE_VECTOR_SIZE)

    def test_validate_feature_vector_invalid_length(self):
        wrong_size_features = [0.0] * (FEATURE_VECTOR_SIZE + 5)
        with self.assertRaises(ValueError):
            validate_feature_vector(wrong_size_features, "test_sample")


if __name__ == "__main__":
    unittest.main()
