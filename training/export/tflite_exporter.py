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


def validate_tflite_interpreter_shapes(
    model_bytes: bytes,
    expected_input_shape: tuple[int, ...] | list[int] = (1, 63),
    expected_output_shape: tuple[int, ...] | list[int] = (1, 1),
) -> None:
    """Instantiates a tf.lite.Interpreter and verifies input/output tensor shapes."""
    interpreter = tf.lite.Interpreter(model_content=model_bytes)
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    if not input_details or not output_details:
        raise ValueError("TFLite model must contain at least one input and output tensor.")

    input_shape = list(input_details[0]["shape"])
    output_shape = list(output_details[0]["shape"])

    exp_in = list(expected_input_shape)
    exp_out = list(expected_output_shape)

    if input_shape != exp_in:
        raise ValueError(
            f"TFLite input tensor shape mismatch: expected {exp_in}, got {input_shape}"
        )

    if output_shape != exp_out:
        raise ValueError(
            f"TFLite output tensor shape mismatch: expected {exp_out}, got {output_shape}"
        )


def export_float32_tflite(
    saved_model_dir: Path,
    output_path: Path,
    expected_input_shape: tuple[int, ...] | list[int] = (1, 63),
    expected_output_shape: tuple[int, ...] | list[int] = (1, 1),
) -> Path:
    ensure_dir(output_path.parent)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    model_bytes = converter.convert()

    validate_tflite_interpreter_shapes(
        model_bytes,
        expected_input_shape=expected_input_shape,
        expected_output_shape=expected_output_shape,
    )

    output_path.write_bytes(model_bytes)
    return output_path


def export_quantized_tflite(
    saved_model_dir: Path,
    output_path: Path,
    expected_input_shape: tuple[int, ...] | list[int] = (1, 63),
    expected_output_shape: tuple[int, ...] | list[int] = (1, 1),
) -> Path:
    """Converts SavedModel to dynamic range int8 quantized TFLite binary, validates tensor shapes, and saves to disk."""
    ensure_dir(output_path.parent)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    model_bytes = converter.convert()

    validate_tflite_interpreter_shapes(
        model_bytes,
        expected_input_shape=expected_input_shape,
        expected_output_shape=expected_output_shape,
    )

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

