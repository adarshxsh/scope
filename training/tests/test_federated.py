"""Unit tests for Python FederatedServerAggregator module."""

import json
import tempfile
import unittest
from pathlib import Path

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.federated.server_aggregator import FederatedServerAggregator
from training.models.mlp import build_baseline_mlp


class TestFederatedServerAggregator(unittest.TestCase):

    def setUp(self) -> None:
        mean = [0.0] * FEATURE_VECTOR_SIZE
        stddev = [1.0] * FEATURE_VECTOR_SIZE
        self.model = build_baseline_mlp(mean=mean, stddev=stddev, learning_rate=0.01)
        self.aggregator = FederatedServerAggregator(learning_rate=0.01)

    def test_aggregate_gradients_updates_weights(self) -> None:
        initial_weights = [w.copy() for w in self.model.get_weights()]

        # Generate mock client DP-SGD gradient updates from 3 devices
        client_updates = [
            {"gradient_delta": np.ones(FEATURE_VECTOR_SIZE, dtype=float).tolist(), "sample_count": 1},
            {"gradient_delta": np.full(FEATURE_VECTOR_SIZE, 0.5, dtype=float).tolist(), "sample_count": 2},
            {"gradient_delta": np.full(FEATURE_VECTOR_SIZE, -0.2, dtype=float).tolist(), "sample_count": 1},
        ]

        updated_model = self.aggregator.aggregate_gradients(self.model, client_updates)
        updated_weights = updated_model.get_weights()

        # Verify weights have been updated by the aggregated gradient step
        self.assertFalse(np.array_equal(initial_weights[0], updated_weights[0]))

    def test_aggregate_weights_fedavg(self) -> None:
        initial_weights = self.model.get_weights()

        # Create two mock client weight sets
        client1_weights = [w + 0.1 for w in initial_weights]
        client2_weights = [w - 0.1 for w in initial_weights]

        client_payloads = [
            {"weights": client1_weights, "sample_count": 1},
            {"weights": client2_weights, "sample_count": 1},
        ]

        updated_model = self.aggregator.aggregate_weights(self.model, client_payloads)
        updated_weights = updated_model.get_weights()

        # FedAvg of (W+0.1) and (W-0.1) should yield baseline W
        for orig, updated in zip(initial_weights, updated_weights):
            np.testing.assert_allclose(orig, updated, atol=1e-5)

    def test_export_tflite_with_checksum(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            out_path = Path(tmp_dir) / "ghost_ai_fed.tflite"
            exported_path, checksum = FederatedServerAggregator.export_tflite_with_checksum(
                self.model, out_path
            )

            self.assertTrue(exported_path.exists())
            self.assertEqual(len(checksum), 64)

            sha_file = exported_path.with_suffix(".sha256")
            self.assertTrue(sha_file.exists())
            self.assertEqual(sha_file.read_text().strip(), checksum)


if __name__ == "__main__":
    unittest.main()
