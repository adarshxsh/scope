"""Shared training configuration."""

from __future__ import annotations

from dataclasses import dataclass


FEATURE_VECTOR_SIZE = 63
RANDOM_SEED = 42

CATEGORICAL_LABELS = ("category", "intent", "urgency")
BINARY_LABELS = (
    "requires_action",
    "is_promotion",
    "is_duplicate_candidate",
    "is_recurring",
    "look_again",
)
TARGET_LABEL = "look_again_score"


@dataclass(frozen=True)
class SplitConfig:
    train_size: float = 0.80
    validation_size: float = 0.10
    test_size: float = 0.10

    def validate(self) -> None:
        total = self.train_size + self.validation_size + self.test_size
        if abs(total - 1.0) > 1e-9:
            raise ValueError(f"Split sizes must add to 1.0, got {total:.4f}.")


@dataclass(frozen=True)
class TrainingConfig:
    epochs: int = 100
    batch_size: int = 64
    learning_rate: float = 1e-3
    early_stopping_patience: int = 12
    reduce_lr_patience: int = 5
    min_delta: float = 1e-4

