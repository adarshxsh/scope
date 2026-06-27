"""SavedModel and TensorFlow Lite export helpers."""

from __future__ import annotations

from pathlib import Path
from typing import Callable

import numpy as np
import tensorflow as tf

from training.utils.io import ensure_dir


def export_saved_model(model: tf.keras.Model, export_dir: Path) -> Path:
    ensure_dir(export_dir.parent)
    if hasattr(model, "export"):
        model.export(str(export_dir))
    else:
        tf.saved_model.save(model, str(export_dir))
    return export_dir


def export_float32_tflite(
    saved_model_dir: Path,
    output_path: Path,
) -> Path:
    ensure_dir(output_path.parent)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    model_bytes = converter.convert()
    output_path.write_bytes(model_bytes)
    return output_path


def _representative_dataset(
    features: np.ndarray,
    max_samples: int = 256,
) -> Callable[[], object]:
    sample = features[:max_samples].astype(np.float32)

    def generate():
        for row in sample:
            yield [row.reshape(1, -1)]

    return generate

