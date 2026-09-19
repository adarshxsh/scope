import unittest
import numpy as np
import tensorflow as tf

from training.dataset.schema import FEATURE_NAMES, FEATURE_VECTOR_SIZE
from training.config import FEATURE_VECTOR_SIZE as CONFIG_FEATURE_SIZE
from training.models.mlp import build_baseline_mlp
from training.dataset.loader import validate_feature_vector
from training.utils.preprocessing import _validate_features


class TestDynamicSchema(unittest.TestCase):
    def test_schema_feature_vector_size_matches_names(self):
        self.assertEqual(FEATURE_VECTOR_SIZE, len(FEATURE_NAMES))
        self.assertEqual(CONFIG_FEATURE_SIZE, len(FEATURE_NAMES))
        self.assertGreater(FEATURE_VECTOR_SIZE, 0)

    def test_build_baseline_mlp_dynamic_feature_dim(self):
        # 50 features
        mean_50 = [0.0] * 50
        stddev_50 = [1.0] * 50
        model_50 = build_baseline_mlp(mean_50, stddev_50, learning_rate=0.001)
        self.assertEqual(model_50.input_shape, (None, 50))

        # 63 features
        mean_63 = [0.0] * 63
        stddev_63 = [1.0] * 63
        model_63 = build_baseline_mlp(mean_63, stddev_63, learning_rate=0.001)
        self.assertEqual(model_63.input_shape, (None, 63))

        # 80 features
        mean_80 = [0.0] * 80
        stddev_80 = [1.0] * 80
        model_80 = build_baseline_mlp(mean_80, stddev_80, learning_rate=0.001)
        self.assertEqual(model_80.input_shape, (None, 80))

    def test_feature_vector_validation_padding_and_truncation(self):
        # Shorter list padded to FEATURE_VECTOR_SIZE
        short_vector = [1.0] * 10
        validated_short = validate_feature_vector(short_vector, "sample_short")
        self.assertEqual(len(validated_short), FEATURE_VECTOR_SIZE)
        self.assertEqual(validated_short[:10], [1.0] * 10)
        self.assertEqual(validated_short[10:], [0.0] * (FEATURE_VECTOR_SIZE - 10))

        # Longer list truncated to FEATURE_VECTOR_SIZE
        long_vector = list(range(100))
        validated_long = _validate_features(long_vector, "sample_long")
        self.assertEqual(len(validated_long), FEATURE_VECTOR_SIZE)
        self.assertEqual(validated_long, list(range(FEATURE_VECTOR_SIZE)))


if __name__ == "__main__":
    unittest.main()
