"""SavedModel and TensorFlow Lite export helpers."""

from __future__ import annotations

from pathlib import Path
from typing import Callable

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.utils.io import ensure_dir


def export_saved_model(
    model: tf.keras.Model,
    export_dir: Path,
    feature_vector_size: int = FEATURE_VECTOR_SIZE,
) -> Path:
    ensure_dir(export_dir.parent)

    @tf.function(
        input_signature=[
            tf.TensorSpec(shape=[None, feature_vector_size], dtype=tf.float32)
        ]
    )
    def serving_fn(x):
        return model(x)

    tf.saved_model.save(
        model,
        str(export_dir),
        signatures={"serving_default": serving_fn},
    )
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


def export_quantized_tflite(
    saved_model_dir: Path,
    output_path: Path,
) -> Path:
    ensure_dir(output_path.parent)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
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

