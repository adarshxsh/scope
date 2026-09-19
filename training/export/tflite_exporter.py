"""SavedModel and TensorFlow Lite export helpers with quantization and shape validation."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Callable, Any

import numpy as np
import tensorflow as tf

from training.config import FEATURE_VECTOR_SIZE
from training.utils.io import ensure_dir

logger = logging.getLogger(__name__)


def export_saved_model(model: tf.keras.Model, export_dir: Path) -> Path:
    """Exports a Keras model to TensorFlow SavedModel format with error guardrails."""
    if not isinstance(model, tf.keras.Model) and not hasattr(model, "save"):
        raise TypeError(f"Expected tf.keras.Model instance, got {type(model).__name__}.")

    export_dir = Path(export_dir)
    ensure_dir(export_dir.parent)

    try:
        if hasattr(model, "export"):
            model.export(str(export_dir))
        else:
            tf.saved_model.save(model, str(export_dir))
        logger.info(f"SavedModel successfully exported to {export_dir}")
    except Exception as e:
        logger.error(f"Failed to export SavedModel to {export_dir}: {e}")
        raise RuntimeError(f"SavedModel export failed: {e}") from e

    return export_dir


def validate_tflite_model(
    model_content_or_path: bytes | Path | str,
    expected_feature_size: int | None = FEATURE_VECTOR_SIZE,
    expected_input_shape: tuple | list | None = None,
) -> dict[str, Any]:
    """Validates the input tensor dimensions, rank, and signatures of a TFLite model binary."""
    if isinstance(model_content_or_path, (str, Path)):
        model_path = Path(model_content_or_path)
        if not model_path.exists():
            raise FileNotFoundError(f"TFLite model binary not found at: {model_path}")
        model_bytes = model_path.read_bytes()
    elif isinstance(model_content_or_path, bytes):
        model_bytes = model_content_or_path
    else:
        raise TypeError(
            f"Expected bytes, Path, or str for model_content_or_path, got {type(model_content_or_path).__name__}"
        )

    if len(model_bytes) == 0:
        raise ValueError("TFLite model binary content is empty (0 bytes).")

    try:
        interpreter = tf.lite.Interpreter(model_content=model_bytes)
        interpreter.allocate_tensors()
    except Exception as e:
        logger.error(f"Failed to load or allocate TFLite model interpreter: {e}")
        raise ValueError(f"Invalid or corrupt TFLite model binary: {e}") from e

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    if not input_details:
        raise ValueError("TFLite model validation failed: model has no input details.")
    if not output_details:
        raise ValueError("TFLite model validation failed: model has no output details.")

    in_det = input_details[0]
    in_shape = tuple(in_det["shape"])
    in_sig = tuple(in_det.get("shape_signature", in_shape))
    in_dtype = str(in_det["dtype"])

    out_det = output_details[0]
    out_shape = tuple(out_det["shape"])
    out_dtype = str(out_det["dtype"])

    # 1. Validate rank (expect 2D: [batch_size, feature_vector_size])
    if len(in_shape) != 2:
        raise ValueError(
            f"TFLite model input tensor rank mismatch: expected 2D tensor [batch, features], got rank {len(in_shape)} with shape {in_shape}."
        )

    # 2. Validate feature vector dimension
    feature_size_found = in_shape[-1]
    if expected_feature_size is not None and feature_size_found != expected_feature_size:
        raise ValueError(
            f"TFLite model input feature vector size mismatch: expected {expected_feature_size}, got {feature_size_found} (shape {in_shape})."
        )

    # 3. Validate against explicit expected_input_shape if provided
    if expected_input_shape is not None and in_shape != tuple(expected_input_shape):
        raise ValueError(
            f"TFLite model input shape mismatch: expected {tuple(expected_input_shape)}, got {in_shape}."
        )

    telemetry = {
        "input_name": in_det.get("name"),
        "input_shape": list(in_shape),
        "input_signature": list(in_sig),
        "input_dtype": in_dtype,
        "output_name": out_det.get("name"),
        "output_shape": list(out_shape),
        "output_dtype": out_dtype,
        "size_bytes": len(model_bytes),
    }

    logger.info(
        f"Validated TFLite model: shape={in_shape}, signature={in_sig}, size={len(model_bytes)} bytes"
    )
    return telemetry


def _representative_dataset(
    features: np.ndarray | list | tuple,
    max_samples: int = 256,
    expected_feature_size: int = FEATURE_VECTOR_SIZE,
) -> Callable[[], object]:
    """Generates a representative dataset callable for int8 post-training quantization calibration."""
    arr = np.asarray(features, dtype=np.float32)

    if arr.size == 0:
        raise ValueError("Representative dataset features array is empty.")
    if arr.ndim != 2:
        raise ValueError(f"Representative dataset features must be a 2D matrix, got rank {arr.ndim}.")
    if arr.shape[1] != expected_feature_size:
        raise ValueError(
            f"Representative dataset feature size mismatch: expected {expected_feature_size}, got {arr.shape[1]}."
        )

    sample = arr[:max_samples].astype(np.float32)

    def generate():
        for row in sample:
            yield [row.reshape(1, -1)]

    return generate


def export_quantized_tflite(
    saved_model_dir: Path,
    output_path: Path,
    representative_data: np.ndarray | list | Callable | None = None,
    int8_fallback: bool = False,
    expected_feature_size: int = FEATURE_VECTOR_SIZE,
) -> Path:
    """Converts a SavedModel artifact to an int8 post-training quantized TensorFlow Lite model."""
    saved_model_dir = Path(saved_model_dir)
    output_path = Path(output_path)

    if not saved_model_dir.exists() or not saved_model_dir.is_dir():
        raise FileNotFoundError(f"SavedModel directory does not exist: {saved_model_dir}")

    ensure_dir(output_path.parent)

    try:
        converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
        converter.optimizations = [tf.lite.Optimize.DEFAULT]

        if representative_data is not None:
            if callable(representative_data):
                converter.representative_dataset = representative_data
            else:
                converter.representative_dataset = _representative_dataset(
                    representative_data, expected_feature_size=expected_feature_size
                )
        else:
            logger.warning(
                "No representative dataset provided for export_quantized_tflite. Applying dynamic range post-training quantization."
            )

        if int8_fallback:
            converter.target_spec.supported_ops = [
                tf.lite.OpsSet.TFLITE_BUILTINS_INT8,
                tf.lite.OpsSet.TFLITE_BUILTINS,
            ]

        model_bytes = converter.convert()
    except Exception as e:
        logger.error(f"Quantized TFLite conversion failed for {saved_model_dir}: {e}")
        raise RuntimeError(f"Quantized TFLite conversion failed: {e}") from e

    # Perform rigorous shape signature and structural validation on converted binary
    telemetry = validate_tflite_model(model_bytes, expected_feature_size=expected_feature_size)

    output_path.write_bytes(model_bytes)
    logger.info(
        f"Exported quantized TFLite model to {output_path} ({telemetry['size_bytes']} bytes)"
    )
    return output_path


def export_float32_tflite(
    saved_model_dir: Path,
    output_path: Path,
    expected_feature_size: int = FEATURE_VECTOR_SIZE,
) -> Path:
    """Converts a SavedModel artifact to a unquantized Float32 TensorFlow Lite model with shape validation."""
    saved_model_dir = Path(saved_model_dir)
    output_path = Path(output_path)

    if not saved_model_dir.exists() or not saved_model_dir.is_dir():
        raise FileNotFoundError(f"SavedModel directory does not exist: {saved_model_dir}")

    ensure_dir(output_path.parent)

    try:
        converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
        model_bytes = converter.convert()
    except Exception as e:
        logger.error(f"Float32 TFLite conversion failed for {saved_model_dir}: {e}")
        raise RuntimeError(f"Float32 TFLite conversion failed: {e}") from e

    # Perform rigorous shape signature and structural validation on converted binary
    telemetry = validate_tflite_model(model_bytes, expected_feature_size=expected_feature_size)

    output_path.write_bytes(model_bytes)
    logger.info(
        f"Exported float32 TFLite model to {output_path} ({telemetry['size_bytes']} bytes)"
    )
    return output_path
