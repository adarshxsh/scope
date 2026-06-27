"""Deterministic dataset splitting and tf.data helpers."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import tensorflow as tf

from training.config import RANDOM_SEED, SplitConfig


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


def split_regression_dataset(
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


def make_tf_dataset(
    features: np.ndarray,
    target: np.ndarray,
    batch_size: int,
    training: bool,
    seed: int = RANDOM_SEED,
) -> tf.data.Dataset:
    dataset = tf.data.Dataset.from_tensor_slices((features.astype(np.float32), target.astype(np.float32)))
    if training:
        dataset = dataset.shuffle(
            buffer_size=len(features),
            seed=seed,
            reshuffle_each_iteration=True,
        )
    return dataset.batch(batch_size).prefetch(tf.data.AUTOTUNE)

