"""Dataset reading and validation."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np

from training.config import FEATURE_VECTOR_SIZE


def load_jsonl_dataset(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise FileNotFoundError(f"Dataset not found: {path}")

    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                payload = json.loads(stripped)
            except json.JSONDecodeError as exc:
                raise ValueError(f"Invalid JSON on line {line_number}: {exc}") from exc
            if not isinstance(payload, dict):
                raise ValueError(f"Line {line_number} must be a JSON object.")
            records.append(payload)

    if not records:
        raise ValueError(f"Dataset is empty: {path}")
    return records


def validate_feature_vector(
    features: Any, sample_name: str, expected_size: int | None = None
) -> list[float]:
    if not isinstance(features, list):
        raise ValueError(f"{sample_name}.features must be a list.")
    if expected_size is not None and len(features) != expected_size:
        raise ValueError(
            f"{sample_name}.features must contain {expected_size} values; "
            f"received {len(features)}."
        )

    vector: list[float] = []
    for index, value in enumerate(features):
        if not isinstance(value, (int, float)):
            raise ValueError(f"{sample_name}.features[{index}] must be numeric.")
        number = float(value)
        if not np.isfinite(number):
            raise ValueError(f"{sample_name}.features[{index}] must be finite.")
        vector.append(number)
    return vector

