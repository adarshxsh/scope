"""Privacy-Preserving Federated Learning (DP-FedAvg) implementation."""

from __future__ import annotations

import math
import re
from typing import Any, Dict, List, Optional, Tuple

import numpy as np


def sanitize_log_text(text: str) -> str:
    """Sanitizes raw log text by scrubbing PII (email, phone, OTP, credentials, financial amounts)."""
    if not text:
        return text

    sanitized = text

    # 1. Email
    sanitized = re.sub(
        r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}",
        "[REDACTED_EMAIL]",
        sanitized,
    )

    # 2. Credentials
    sanitized = re.sub(
        r"\b(bearer|token|key|secret|auth)[=\s:]+[A-Za-z0-9_-]{8,}\b",
        r"\1=[REDACTED_CREDENTIAL]",
        sanitized,
        flags=re.IGNORECASE,
    )

    # 3. OTP codes
    sanitized = re.sub(
        r"\b(code|otp|verification|pin|password|token)\b[:\s]*\d{4,8}\b",
        r"\1: [REDACTED_OTP]",
        sanitized,
        flags=re.IGNORECASE,
    )

    # 4. Currency amounts
    sanitized = re.sub(
        r"(\$|₹|Rs\.?|USD|EUR|€|£)\s*\d+(?:[\.,]\d+)?",
        "[REDACTED_AMOUNT]",
        sanitized,
        flags=re.IGNORECASE,
    )

    # 5. Phone numbers
    sanitized = re.sub(
        r"(\+\d{1,4}[\s.-]?)?\(?\d{2,4}\)?([\s.-]?\d{3,4}){1,2}\b",
        "[REDACTED_PHONE]",
        sanitized,
    )

    return sanitized


def clip_gradient_l2(vector: np.ndarray, clip_norm: float) -> Tuple[np.ndarray, float]:
    """Clips vector to maximum L2 norm `clip_norm`. Returns (clipped_vector, original_norm)."""
    if clip_norm <= 0:
        raise ValueError("clip_norm must be strictly positive")

    norm = float(np.linalg.norm(vector))
    if not np.isfinite(norm):
        raise ValueError("Vector contains non-finite numerical value (NaN or Infinity)")

    if norm == 0.0 or norm <= clip_norm:
        return vector.copy(), norm

    scaling_factor = clip_norm / norm
    return vector * scaling_factor, norm


def add_gaussian_noise(vector: np.ndarray, noise_scale: float, rng: Optional[np.random.Generator] = None) -> np.ndarray:
    """Adds zero-mean Gaussian noise N(0, noise_scale^2) to vector."""
    if noise_scale < 0:
        raise ValueError("noise_scale cannot be negative")
    if noise_scale == 0.0:
        return vector.copy()

    if rng is None:
        rng = np.random.default_rng()

    noise = rng.normal(loc=0.0, scale=noise_scale, size=vector.shape)
    return vector + noise


class DPFedAvgClient:
    """Simulates an on-device Differential Privacy Federated Learning client."""

    def __init__(
        self,
        client_id: str,
        clip_norm: float = 1.0,
        noise_multiplier: float = 0.1,
        learning_rate: float = 0.01,
        rng: Optional[np.random.Generator] = None,
    ) -> None:
        self.client_id = sanitize_log_text(client_id)
        self.clip_norm = clip_norm
        self.noise_multiplier = noise_multiplier
        self.learning_rate = learning_rate
        self.rng = rng or np.random.default_rng()

    def compute_local_update(
        self,
        global_weights: np.ndarray,
        features: np.ndarray,
        targets: np.ndarray,
    ) -> Dict[str, Any]:
        """Computes DP-protected weight delta from local client batch."""
        sanitized_id = self.client_id
        if len(features) == 0 or len(features) != len(targets):
            return {
                "client_id": sanitized_id,
                "success": False,
                "status": "fallback_invalid_batch",
                "delta": None,
                "error": "Features and targets must be non-empty and equal length.",
            }

        try:
            num_samples = len(features)
            num_features = len(global_weights)

            # Compute local linear model gradient: dL/dw = 2/N * sum (w.x - y) * x
            predictions = np.dot(features, global_weights)
            errors = predictions - targets.flatten()
            raw_gradient = (2.0 / num_samples) * np.dot(features.T, errors)

            if not np.all(np.isfinite(raw_gradient)):
                raise ValueError("Gradient contains NaN or Infinite values.")

            # Apply L2 norm clipping
            clipped_grad, initial_norm = clip_gradient_l2(raw_gradient, self.clip_norm)
            clipped_norm = float(np.linalg.norm(clipped_grad))

            # Apply Gaussian DP noise
            noise_scale = self.noise_multiplier * self.clip_norm
            dp_gradient = add_gaussian_noise(clipped_grad, noise_scale, rng=self.rng)

            # Weight delta: delta_w = - eta * grad_dp
            weight_delta = -self.learning_rate * dp_gradient

            if not np.all(np.isfinite(weight_delta)):
                raise ValueError("Weight update contains non-finite values.")

            return {
                "client_id": sanitized_id,
                "success": True,
                "status": "success",
                "delta": weight_delta,
                "sample_count": num_samples,
                "initial_norm": initial_norm,
                "clipped_norm": clipped_norm,
                "noise_scale": noise_scale,
            }
        except Exception as err:
            return {
                "client_id": sanitized_id,
                "success": False,
                "status": "fallback_error",
                "delta": None,
                "error": sanitize_log_text(str(err)),
            }


class DPFedAvgServer:
    """Central server for DP-FedAvg aggregation with client update validation and fallback recovery."""

    def __init__(self, initial_weights: np.ndarray, target_delta: float = 1e-5) -> None:
        if not np.all(np.isfinite(initial_weights)):
            raise ValueError("Initial weights contain non-finite values.")
        self.weights = initial_weights.copy()
        self.target_delta = target_delta
        self.rounds_completed = 0
        self.audit_history: List[Dict[str, Any]] = []

    def aggregate_round(
        self,
        round_id: str,
        client_updates: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        """Aggregates valid client updates into global model weights."""
        sanitized_round_id = sanitize_log_text(round_id)
        valid_updates = [u for u in client_updates if u.get("success") and u.get("delta") is not None]

        if not valid_updates:
            record = {
                "round_id": sanitized_round_id,
                "status": "fallback_no_valid_clients",
                "valid_clients": 0,
                "total_clients": len(client_updates),
                "details": "No valid client updates received in round. Server maintained base weights.",
            }
            self.audit_history.append(record)
            return {"success": False, "weights": self.weights.copy(), "audit": record}

        try:
            # Average weight deltas across valid clients
            deltas = [u["delta"] for u in valid_updates]
            mean_delta = np.mean(deltas, axis=0)

            if not np.all(np.isfinite(mean_delta)):
                raise ValueError("Aggregated delta contains non-finite values.")

            self.weights += mean_delta
            self.rounds_completed += 1

            record = {
                "round_id": sanitized_round_id,
                "status": "success",
                "valid_clients": len(valid_updates),
                "total_clients": len(client_updates),
                "aggregated_delta_norm": float(np.linalg.norm(mean_delta)),
                "details": f"Successfully aggregated updates from {len(valid_updates)} clients.",
            }
            self.audit_history.append(record)
            return {"success": True, "weights": self.weights.copy(), "audit": record}
        except Exception as err:
            record = {
                "round_id": sanitized_round_id,
                "status": "fallback_error",
                "valid_clients": len(valid_updates),
                "total_clients": len(client_updates),
                "details": f"Fallback triggered: {sanitize_log_text(str(err))}",
            }
            self.audit_history.append(record)
            return {"success": False, "weights": self.weights.copy(), "audit": record}
