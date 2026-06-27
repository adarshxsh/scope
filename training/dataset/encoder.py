"""Label encoders for future multi-task heads."""

from __future__ import annotations

from typing import Any

import numpy as np

from training.config import BINARY_LABELS, CATEGORICAL_LABELS, TARGET_LABEL


def encode_labels(
    raw_labels: dict[str, list[Any]],
) -> tuple[dict[str, np.ndarray], dict[str, dict[str, Any]]]:
    encoded: dict[str, np.ndarray] = {}
    encoders: dict[str, dict[str, Any]] = {}

    for key in CATEGORICAL_LABELS:
        classes = sorted(set(str(value) for value in raw_labels[key]))
        mapping = {label: index for index, label in enumerate(classes)}
        encoded[key] = np.asarray(
            [mapping[str(value)] for value in raw_labels[key]], dtype=np.int64
        )
        encoders[key] = {
            "type": "categorical",
            "classes": classes,
            "class_to_id": mapping,
        }

    for key in BINARY_LABELS:
        encoded[key] = np.asarray(raw_labels[key], dtype=np.float32)
        encoders[key] = {
            "type": "binary",
            "class_to_id": {"false": 0, "true": 1},
        }

    return encoded, encoders


def validate_labels(labels: Any, sample_name: str) -> dict[str, Any]:
    if not isinstance(labels, dict):
        raise ValueError(f"{sample_name}.labels must be an object.")

    required = (*CATEGORICAL_LABELS, *BINARY_LABELS, TARGET_LABEL)
    missing = [key for key in required if key not in labels]
    if missing:
        raise ValueError(f"{sample_name}.labels missing required keys: {missing}")

    for key in CATEGORICAL_LABELS:
        if labels[key] is None or str(labels[key]).strip() == "":
            raise ValueError(f"{sample_name}.labels.{key} must be non-empty.")

    score = labels[TARGET_LABEL]
    if not isinstance(score, (int, float)) or not np.isfinite(float(score)):
        raise ValueError(f"{sample_name}.labels.{TARGET_LABEL} must be finite numeric.")

    for key in BINARY_LABELS:
        if not isinstance(labels[key], bool):
            raise ValueError(f"{sample_name}.labels.{key} must be boolean.")

    return labels
