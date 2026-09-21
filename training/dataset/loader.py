"""Dataset reading and validation."""

from __future__ import annotations

import hashlib
import json
import warnings
from pathlib import Path
from typing import Any

import numpy as np

from training.config import FEATURE_VECTOR_SIZE


def compute_file_sha256(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def verify_dataset_hash(path: Path, strict_verify: bool = False) -> None:
    sidecar_path = path.parent / f"{path.name}.sha256"
    manifest_named_path = path.parent / f"{path.name}.manifest.json"
    manifest_default_path = path.parent / "manifest.json"

    expected_hash: str | None = None

    if sidecar_path.exists():
        content = sidecar_path.read_text(encoding="utf-8").strip()
        if content:
            expected_hash = content.split()[0].lower()
    elif manifest_named_path.exists():
        try:
            data = json.loads(manifest_named_path.read_text(encoding="utf-8"))
            if isinstance(data, dict) and "sha256" in data:
                expected_hash = str(data["sha256"]).lower()
        except Exception:
            pass
    elif manifest_default_path.exists():
        try:
            data = json.loads(manifest_default_path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                if data.get("file_name") == path.name and "sha256" in data:
                    expected_hash = str(data["sha256"]).lower()
                elif "sha256" in data:
                    expected_hash = str(data["sha256"]).lower()
        except Exception:
            pass

    if expected_hash is None:
        msg = f"No SHA-256 digest or manifest file found for dataset {path}."
        if strict_verify:
            raise ValueError(msg)
        else:
            warnings.warn(msg)
            return

    actual_hash = compute_file_sha256(path).lower()
    if actual_hash != expected_hash:
        raise ValueError(
            f"SHA-256 digest mismatch for dataset {path}: expected {expected_hash}, got {actual_hash}"
        )


def load_jsonl_dataset(path: Path, strict_verify: bool = False) -> list[dict[str, Any]]:
    if not path.exists():
        raise FileNotFoundError(f"Dataset not found: {path}")

    verify_dataset_hash(path, strict_verify=strict_verify)

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


def validate_feature_vector(features: Any, sample_name: str) -> list[float]:
    if not isinstance(features, list):
        raise ValueError(f"{sample_name}.features must be a list.")
    if len(features) != FEATURE_VECTOR_SIZE:
        raise ValueError(
            f"{sample_name}.features must contain {FEATURE_VECTOR_SIZE} values; "
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

