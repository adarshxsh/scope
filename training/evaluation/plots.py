"""Evaluation plot generation."""

from __future__ import annotations

import os
from pathlib import Path

os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/matplotlib")

import matplotlib.pyplot as plt
import numpy as np

from training.utils.io import ensure_dir


def plot_training_history(history, output_dir: Path) -> None:
    ensure_dir(output_dir)
    history_dict = history.history

    _plot_series(
        output_dir / "loss.png",
        "Loss",
        history_dict,
        "loss",
        "val_loss",
        "MSE",
    )
    _plot_series(
        output_dir / "mae.png",
        "MAE",
        history_dict,
        "mae",
        "val_mae",
        "MAE",
    )
    _plot_series(
        output_dir / "rmse.png",
        "RMSE",
        history_dict,
        "rmse",
        "val_rmse",
        "RMSE",
    )
    if "r2" in history_dict:
        _plot_series(
            output_dir / "r2.png",
            "R2",
            history_dict,
            "r2",
            "val_r2",
            "R2",
        )


def plot_regression_results(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    output_dir: Path,
) -> None:
    ensure_dir(output_dir)
    true = y_true.reshape(-1)
    pred = y_pred.reshape(-1)
    residuals = true - pred

    plt.figure(figsize=(7, 7))
    plt.scatter(true, pred, alpha=0.6)
    lower = min(true.min(), pred.min())
    upper = max(true.max(), pred.max())
    plt.plot([lower, upper], [lower, upper], "r--", linewidth=1)
    plt.xlabel("Actual look_again_score")
    plt.ylabel("Predicted look_again_score")
    plt.title("Predicted vs Actual")
    plt.tight_layout()
    plt.savefig(output_dir / "predicted_vs_actual.png", dpi=160)
    plt.close()

    plt.figure(figsize=(8, 5))
    plt.hist(residuals, bins=40, alpha=0.8)
    plt.xlabel("Residual")
    plt.ylabel("Count")
    plt.title("Residual Distribution")
    plt.tight_layout()
    plt.savefig(output_dir / "residuals.png", dpi=160)
    plt.close()


def _plot_series(
    path: Path,
    title: str,
    history: dict[str, list[float]],
    train_key: str,
    validation_key: str,
    ylabel: str,
) -> None:
    if train_key not in history:
        return
    plt.figure(figsize=(8, 5))
    plt.plot(history[train_key], label=train_key)
    if validation_key in history:
        plt.plot(history[validation_key], label=validation_key)
    plt.xlabel("Epoch")
    plt.ylabel(ylabel)
    plt.title(title)
    plt.legend()
    plt.tight_layout()
    plt.savefig(path, dpi=160)
    plt.close()

