"""Dataset validation, label encoding, and deterministic splitting."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

from training.config import (
    BINARY_LABELS,
    CATEGORICAL_LABELS,
    FEATURE_VECTOR_SIZE,
    RANDOM_SEED,
    SplitConfig,
    TARGET_LABEL,
)
from training.utils.feature_extractor import extract_features


@dataclass(frozen=True)
class EncodedDataset:
    features: np.ndarray
    target: np.ndarray
    encoded_labels: dict[str, np.ndarray]
    label_encoders: dict[str, dict[str, Any]]
    raw_labels: dict[str, list[Any]]


@dataclass(frozen=True)
class DatasetSplit:
    x_train: np.ndarray
    y_train: np.ndarray
    x_val: np.ndarray
    y_val: np.ndarray
    x_test: np.ndarray
    y_test: np.ndarray
    train_indices: np.ndarray
    validation_indices: np.ndarray
    test_indices: np.ndarray


def build_dataset(records: list[dict[str, Any]]) -> EncodedDataset:
    features: list[list[float]] = []
    target: list[float] = []
    raw_labels: dict[str, list[Any]] = {
        key: [] for key in (*CATEGORICAL_LABELS, *BINARY_LABELS, TARGET_LABEL)
    }

    for index, record in enumerate(records):
        sample_id = f"sample[{index}]"
        
        # 1. Extract or get features
        features_val = record.get("features")
        if features_val is None or not isinstance(features_val, list):
            features_val = extract_features(record)
            
        vector = _validate_features(features_val, sample_id)
        
        # 2. Get or construct labels
        raw_labels_dict = record.get("labels") or {}
        labels_val = {
            "category": raw_labels_dict.get("category_class") or record.get("category") or "",
            "intent": raw_labels_dict.get("intent") or record.get("intent") or "",
            "urgency": raw_labels_dict.get("urgency") or record.get("urgency") or "",
            "requires_action": raw_labels_dict.get("requires_action") if raw_labels_dict.get("requires_action") is not None else record.get("requires_action", False),
            "is_promotion": raw_labels_dict.get("is_promotion") if raw_labels_dict.get("is_promotion") is not None else record.get("is_promotion", False),
            "is_duplicate_candidate": raw_labels_dict.get("is_duplicate_candidate") if raw_labels_dict.get("is_duplicate_candidate") is not None else record.get("is_duplicate_candidate", False),
            "is_recurring": raw_labels_dict.get("is_recurring") if raw_labels_dict.get("is_recurring") is not None else record.get("is_recurring", False),
            "look_again": raw_labels_dict.get("look_again") if raw_labels_dict.get("look_again") is not None else record.get("look_again", False),
            "look_again_score": record.get("look_again_score") or raw_labels_dict.get("look_again_score") or 0.0
        }
        
        labels = _validate_labels(labels_val, sample_id)

        features.append(vector)
        score = float(labels[TARGET_LABEL])
        target.append(score)
        raw_labels[TARGET_LABEL].append(score)

        for key in CATEGORICAL_LABELS:
            value = str(labels[key])
            raw_labels[key].append(value)
        for key in BINARY_LABELS:
            value = _validate_bool(labels[key], f"{sample_id}.labels.{key}")
            raw_labels[key].append(value)

    encoded_labels, encoders = _encode_labels(raw_labels)

    return EncodedDataset(
        features=np.asarray(features, dtype=np.float32),
        target=np.asarray(target, dtype=np.float32).reshape(-1, 1),
        encoded_labels=encoded_labels,
        label_encoders=encoders,
        raw_labels=raw_labels,
    )


def split_dataset(
    features: np.ndarray,
    target: np.ndarray,
    split_config: SplitConfig,
    seed: int = RANDOM_SEED,
) -> DatasetSplit:
    split_config.validate()
    sample_count = len(features)
    if sample_count < 10:
        raise ValueError(
            "At least 10 samples are required for an 80/10/10 split. "
            f"Received {sample_count}."
        )

    rng = np.random.default_rng(seed)
    indices = rng.permutation(sample_count)

    train_end = int(round(sample_count * split_config.train_size))
    validation_count = int(round(sample_count * split_config.validation_size))
    validation_end = train_end + validation_count

    train_indices = indices[:train_end]
    validation_indices = indices[train_end:validation_end]
    test_indices = indices[validation_end:]

    if len(validation_indices) == 0 or len(test_indices) == 0:
        raise ValueError("Validation and test splits must both contain samples.")

    return DatasetSplit(
        x_train=features[train_indices],
        y_train=target[train_indices],
        x_val=features[validation_indices],
        y_val=target[validation_indices],
        x_test=features[test_indices],
        y_test=target[test_indices],
        train_indices=train_indices,
        validation_indices=validation_indices,
        test_indices=test_indices,
    )


def normalization_stats(features: np.ndarray) -> dict[str, list[float]]:
    mean = features.mean(axis=0, dtype=np.float64)
    variance = features.var(axis=0, dtype=np.float64)
    return {
        "mean": mean.astype(float).tolist(),
        "variance": variance.astype(float).tolist(),
    }


def _validate_features(value: Any, sample_id: str) -> list[float]:
    if not isinstance(value, list):
        raise ValueError(f"{sample_id}.features must be a list.")
    if len(value) != FEATURE_VECTOR_SIZE:
        raise ValueError(
            f"{sample_id}.features must contain {FEATURE_VECTOR_SIZE} values; "
            f"received {len(value)}."
        )

    vector: list[float] = []
    for feature_index, raw in enumerate(value):
        if not isinstance(raw, (int, float)):
            raise ValueError(
                f"{sample_id}.features[{feature_index}] must be numeric."
            )
        number = float(raw)
        if not np.isfinite(number):
            raise ValueError(
                f"{sample_id}.features[{feature_index}] must be finite."
            )
        vector.append(number)
    return vector


def _validate_labels(value: Any, sample_id: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{sample_id}.labels must be an object.")

    required = (*CATEGORICAL_LABELS, *BINARY_LABELS, TARGET_LABEL)
    missing = [key for key in required if key not in value]
    if missing:
        raise ValueError(f"{sample_id}.labels missing required keys: {missing}")

    for key in CATEGORICAL_LABELS:
        if value[key] is None or str(value[key]).strip() == "":
            raise ValueError(f"{sample_id}.labels.{key} must be a non-empty string.")

    score = value[TARGET_LABEL]
    if not isinstance(score, (int, float)) or not np.isfinite(float(score)):
        raise ValueError(f"{sample_id}.labels.{TARGET_LABEL} must be finite numeric.")

    return value


def _validate_bool(value: Any, name: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{name} must be a boolean.")
    return value


def _encode_labels(
    raw_labels: dict[str, list[Any]]
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

