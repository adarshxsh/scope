"""SavedModel and TensorFlow Lite export helpers."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Callable

import numpy as np
import tensorflow as tf

from training.utils.io import ensure_dir


def generate_model_manifest(
    tflite_path: Path,
    manifest_path: Path | None = None,
    version: str = "1.0.0",
    input_shapes: list | None = None,
    output_shapes: list | None = None,
    target_engine: str = "GhostAI",
) -> Path:
    """Generates a model_manifest.json metadata file alongside exported TFLite binaries."""
    if manifest_path is None:
        manifest_path = tflite_path.parent / "model_manifest.json"

    model_bytes = tflite_path.read_bytes()
    sha256_checksum = hashlib.sha256(model_bytes).hexdigest()

    if input_shapes is None:
        input_shapes = [[1, 63]]
    if output_shapes is None:
        output_shapes = [[1, 1]]

    manifest = {
        "version": version,
        "sha256": sha256_checksum,
        "checksum": sha256_checksum,
        "input_tensor_shapes": input_shapes,
        "output_tensor_shapes": output_shapes,
        "target_engine": target_engine,
    }

    ensure_dir(manifest_path.parent)
    manifest_path.write_text(json.dumps(manifest, indent=2))
    return manifest_path


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
    generate_manifest: bool = True,
    version: str = "1.0.0",
    target_engine: str = "GhostAI",
) -> Path:
    ensure_dir(output_path.parent)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    model_bytes = converter.convert()
    output_path.write_bytes(model_bytes)

    if generate_manifest:
        generate_model_manifest(
            tflite_path=output_path,
            version=version,
            target_engine=target_engine,
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

