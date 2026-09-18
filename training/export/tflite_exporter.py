"""SavedModel and TensorFlow Lite export helpers with quantization and shape validation."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.utils.io import ensure_dir


def validate_tflite_export(
    tflite_path: Path,
    expected_input_shape: tuple[int, ...] | list[int] | None = (1, FEATURE_VECTOR_SIZE),
    expected_dtype: Any = np.float32,
) -> dict[str, Any]:
    """Validates TFLite model binary for header magic bytes, tensor shapes, and inference execution."""
    if not tflite_path.exists():
        raise FileNotFoundError(f"TFLite model file not found at {tflite_path}")

    model_bytes = tflite_path.read_bytes()
    if len(model_bytes) < 8:
        raise ValueError(
            f"Invalid TFLite binary at {tflite_path}: file size ({len(model_bytes)} bytes) too small"
        )

    # Check FlatBuffer header magic bytes at offset 4..7 ("TFL3")
    magic = model_bytes[4:8]
    if magic != b"TFL3":
        raise ValueError(
            f"Invalid TFLite FlatBuffer magic header at {tflite_path}: expected b'TFL3', got {magic!r}"
        )

    try:
        interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
        interpreter.allocate_tensors()
    except Exception as e:
        raise ValueError(f"Failed to load TFLite model with Interpreter: {e}") from e

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    if not input_details:
        raise ValueError("TFLite model has no input details")
    if not output_details:
        raise ValueError("TFLite model has no output details")

    actual_shape = list(input_details[0]["shape"])
    actual_dtype = input_details[0]["dtype"]

    if expected_input_shape is not None:
        expected_shape = list(expected_input_shape)
        if len(actual_shape) != len(expected_shape):
            raise ValueError(
                f"Input rank mismatch: expected {len(expected_shape)} dimensions ({expected_shape}), got {len(actual_shape)} ({actual_shape})"
            )
        for i, (actual_dim, expected_dim) in enumerate(zip(actual_shape, expected_shape)):
            if expected_dim is not None and expected_dim != -1 and actual_dim != expected_dim:
                raise ValueError(
                    f"Input shape dimension mismatch at index {i}: expected {expected_dim}, got {actual_dim} (shape: {actual_shape})"
                )

    if expected_dtype is not None:
        expected_dt = np.dtype(expected_dtype)
        actual_dt = np.dtype(actual_dtype)
        if actual_dt != expected_dt:
            raise TypeError(
                f"Input dtype mismatch: expected {expected_dt}, got {actual_dt}"
            )

    # Perform dummy test inference run
    try:
        sample_input = np.zeros(actual_shape, dtype=actual_dtype)
        interpreter.set_tensor(input_details[0]["index"], sample_input)
        interpreter.invoke()
        output_data = interpreter.get_tensor(output_details[0]["index"])
    except Exception as e:
        raise RuntimeError(f"TFLite dummy inference execution failed: {e}") from e

    return {
        "file_size_bytes": len(model_bytes),
        "input_shape": actual_shape,
        "input_dtype": np.dtype(actual_dtype).name,
        "output_shape": list(output_details[0]["shape"]),
        "output_dtype": np.dtype(output_details[0]["dtype"]).name,
        "dummy_output_shape": list(output_data.shape),
    }


def export_saved_model(
    model: tf.keras.Model,
    export_dir: Path,
    input_shape: tuple[int, ...] | list[int] = (1, FEATURE_VECTOR_SIZE),
) -> Path:
    """Exports Keras model as SavedModel with explicit serving input signature."""
    ensure_dir(export_dir.parent)

    feature_dim = input_shape[1] if len(input_shape) > 1 else FEATURE_VECTOR_SIZE

    @tf.function(
        input_signature=[
            tf.TensorSpec(
                shape=[None, feature_dim],
                dtype=tf.float32,
                name="features",
            )
        ]
    )
    def serving_fn(features):
        return model(features)

    signatures = {"serving_default": serving_fn}

    if hasattr(model, "export"):
        try:
            model.export(str(export_dir))
        except Exception:
            tf.saved_model.save(model, str(export_dir), signatures=signatures)
    else:
        tf.saved_model.save(model, str(export_dir), signatures=signatures)

    return export_dir


def export_float32_tflite(
    saved_model_dir: Path,
    output_path: Path,
    expected_input_shape: tuple[int, ...] | list[int] | None = (1, FEATURE_VECTOR_SIZE),
    expected_dtype: Any = np.float32,
) -> Path:
    """Exports SavedModel to unquantized float32 TFLite binary with shape validation."""
    ensure_dir(output_path.parent)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    model_bytes = converter.convert()
    output_path.write_bytes(model_bytes)

    validate_tflite_export(
        output_path,
        expected_input_shape=expected_input_shape,
        expected_dtype=expected_dtype,
    )
    return output_path


def export_quantized_tflite(
    saved_model_dir: Path,
    output_path: Path,
    representative_data: np.ndarray | None = None,
    expected_input_shape: tuple[int, ...] | list[int] | None = (1, FEATURE_VECTOR_SIZE),
    expected_dtype: Any = np.float32,
) -> Path:
    """Exports SavedModel to INT8 post-training quantized TFLite binary with shape validation."""
    ensure_dir(output_path.parent)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]

    if representative_data is not None:
        converter.representative_dataset = _representative_dataset(representative_data)

    model_bytes = converter.convert()
    output_path.write_bytes(model_bytes)

    validate_tflite_export(
        output_path,
        expected_input_shape=expected_input_shape,
        expected_dtype=expected_dtype,
    )
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


