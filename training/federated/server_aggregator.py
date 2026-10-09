"""Server-side Federated Averaging (FedAvg) aggregator for AttentionOS."""

from __future__ import annotations

import hashlib
import logging
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE

logger = logging.getLogger(__name__)


class FederatedServerAggregator:
    """Implements Federated Averaging (FedAvg) to combine client model updates
    without harvesting or storing cleartext notification features or PII.
    """

    def __init__(self, learning_rate: float = 0.01) -> None:
        self.learning_rate = learning_rate

    def aggregate_gradients(
        self,
        global_model: tf.keras.Model,
        client_updates: list[dict[str, Any]],
    ) -> tf.keras.Model:
        """Aggregates anonymized 63-dimensional client DP-SGD gradient deltas using FedAvg
        and applies the update step to the global model parameters.
        """
        if not client_updates:
            logger.warning("No client updates provided for aggregation.")
            return global_model

        total_samples = 0
        aggregated_gradient = np.zeros(FEATURE_VECTOR_SIZE, dtype=np.float32)

        for update in client_updates:
            grad_delta = np.array(update["gradient_delta"], dtype=np.float32)
            if grad_delta.shape[0] != FEATURE_VECTOR_SIZE:
                raise ValueError(
                    f"Gradient vector size mismatch: expected {FEATURE_VECTOR_SIZE}, got {grad_delta.shape[0]}"
                )
            sample_count = int(update.get("sample_count", 1))
            aggregated_gradient += grad_delta * sample_count
            total_samples += sample_count

        if total_samples > 0:
            aggregated_gradient /= float(total_samples)

        # Apply aggregated feature gradient update to model trainable weights
        weights = global_model.get_weights()
        if len(weights) > 0:
            # First dense layer weights: shape (63, 128)
            # Update weights: W_new = W_old - learning_rate * grad (outer product / broadcasting)
            first_layer_weights = weights[0]
            if first_layer_weights.shape[0] == FEATURE_VECTOR_SIZE:
                # Expand aggregated gradient across layer neurons
                grad_matrix = np.tile(
                    aggregated_gradient[:, np.newaxis],
                    (1, first_layer_weights.shape[1]),
                )
                weights[0] = first_layer_weights - (self.learning_rate * grad_matrix)
                global_model.set_weights(weights)

        logger.info(
            f"Successfully aggregated {len(client_updates)} client updates over {total_samples} samples via FedAvg."
        )
        return global_model

    def aggregate_weights(
        self,
        global_model: tf.keras.Model,
        client_weight_payloads: list[dict[str, Any]],
    ) -> tf.keras.Model:
        """Aggregates full model layer weights across multiple client endpoints using FedAvg."""
        if not client_weight_payloads:
            logger.warning("No client weight payloads provided for aggregation.")
            return global_model

        total_samples = 0
        first_payload = client_weight_payloads[0]["weights"]
        accumulated_weights = [np.zeros_like(w, dtype=np.float32) for w in first_payload]

        for payload in client_weight_payloads:
            weights = payload["weights"]
            sample_count = int(payload.get("sample_count", 1))
            total_samples += sample_count
            for i, layer_weight in enumerate(weights):
                accumulated_weights[i] += np.array(layer_weight, dtype=np.float32) * sample_count

        if total_samples > 0:
            avg_weights = [w / float(total_samples) for w in accumulated_weights]
            global_model.set_weights(avg_weights)

        logger.info(
            f"Successfully aggregated full model weights across {len(client_weight_payloads)} clients using FedAvg."
        )
        return global_model

    @staticmethod
    def export_tflite_with_checksum(
        global_model: tf.keras.Model,
        output_path: Path,
    ) -> tuple[Path, str]:
        """Converts global Keras model to TFLite FlatBuffer and returns path along with SHA-256 checksum."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        converter = tf.lite.TFLiteConverter.from_keras_model(global_model)
        tflite_model_bytes = converter.convert()

        output_path.write_bytes(tflite_model_bytes)
        checksum = hashlib.sha256(tflite_model_bytes).hexdigest()

        checksum_file = output_path.with_suffix(".sha256")
        checksum_file.write_text(checksum)

        logger.info(f"Exported aggregated global TFLite model to {output_path} (SHA-256: {checksum})")
        return output_path, checksum
