"""Tests for arbitrary feature vector length support in training pipeline."""

import unittest
import numpy as np

from training.dataset.loader import validate_feature_vector
from training.utils.preprocessing import build_dataset, _validate_features


class TestArbitraryFeatures(unittest.TestCase):
    def test_validate_feature_vector_arbitrary_length(self):
        feat_50 = [float(i) for i in range(50)]
        validated = validate_feature_vector(feat_50, "test_50", expected_size=50)
        self.assertEqual(len(validated), 50)

        feat_80 = [float(i) for i in range(80)]
        validated_80 = validate_feature_vector(feat_80, "test_80", expected_size=80)
        self.assertEqual(len(validated_80), 80)

    def test_validate_feature_vector_mismatch_raises(self):
        feat_50 = [float(i) for i in range(50)]
        with self.assertRaises(ValueError):
            validate_feature_vector(feat_50, "test_mismatch", expected_size=63)

    def test_build_dataset_with_variable_feature_dimensions(self):
        records_50 = [
            {
                "features": [1.0] * 50,
                "labels": {
                    "category_class": "Email",
                    "intent": "review",
                    "urgency": "medium",
                    "requires_action": False,
                    "is_promotion": False,
                    "is_duplicate_candidate": False,
                    "is_recurring": False,
                    "look_again": False,
                    "look_again_score": 0.5,
                },
            }
            for _ in range(12)
        ]
        dataset_50 = build_dataset(records_50)
        self.assertEqual(dataset_50.features.shape, (12, 50))

        records_75 = [
            {
                "features": [2.0] * 75,
                "labels": {
                    "category_class": "Delivery",
                    "intent": "track",
                    "urgency": "high",
                    "requires_action": True,
                    "is_promotion": False,
                    "is_duplicate_candidate": False,
                    "is_recurring": False,
                    "look_again": True,
                    "look_again_score": 0.8,
                },
            }
            for _ in range(12)
        ]
        dataset_75 = build_dataset(records_75)
        self.assertEqual(dataset_75.features.shape, (12, 75))


if __name__ == "__main__":
    unittest.main()
