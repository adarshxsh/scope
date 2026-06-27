"""Regression and future categorical reporting."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any

import numpy as np
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    mean_absolute_error,
    mean_squared_error,
    r2_score,
)

from training.utils.io import ensure_dir


def regression_metrics(y_true: np.ndarray, y_pred: np.ndarray) -> dict[str, float]:
    true = y_true.reshape(-1)
    pred = y_pred.reshape(-1)
    mse = mean_squared_error(true, pred)
    return {
        "mse": float(mse),
        "mae": float(mean_absolute_error(true, pred)),
        "rmse": float(np.sqrt(mse)),
        "r2": float(r2_score(true, pred)),
    }


def write_history_csv(history: Any, output_path: Path) -> None:
    ensure_dir(output_path.parent)
    history_dict = history.history
    keys = list(history_dict.keys())
    epochs = len(next(iter(history_dict.values()), []))

    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["epoch", *keys])
        writer.writeheader()
        for epoch in range(epochs):
            row = {"epoch": epoch + 1}
            for key in keys:
                row[key] = history_dict[key][epoch]
            writer.writerow(row)


def write_confusion_reports(
    y_true_by_label: dict[str, np.ndarray],
    y_pred_by_label: dict[str, np.ndarray],
    encoders: dict[str, dict[str, Any]],
    output_dir: Path,
) -> None:
    """Write confusion reports for future multi-task categorical heads.

    The current baseline trains only look_again_score. This helper is wired for
    later use when category, intent, and urgency predictions are added.
    """
    ensure_dir(output_dir)
    for label_name, y_true in y_true_by_label.items():
        if label_name not in y_pred_by_label:
            continue
        encoder = encoders.get(label_name, {})
        class_names = encoder.get("classes", [])
        y_pred = y_pred_by_label[label_name]
        report = classification_report(
            y_true,
            y_pred,
            target_names=class_names or None,
            zero_division=0,
            output_dict=True,
        )
        matrix = confusion_matrix(y_true, y_pred).tolist()
        payload = {
            "label": label_name,
            "classes": class_names,
            "classification_report": report,
            "confusion_matrix": matrix,
        }
        path = output_dir / f"{label_name}_confusion_report.json"
        path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")

