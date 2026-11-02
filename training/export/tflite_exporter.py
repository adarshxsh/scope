"""SavedModel and TensorFlow Lite export helpers."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
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


def compute_sha256(file_path: Path) -> str:
    """Compute SHA256 checksum of a binary file."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def create_model_release_bundle(
    tflite_path: Path,
    export_dir: Path,
    model_name: str = "ghost_ai",
    version: str = "1.0.0",
    schema_version: str = "1.0.0",
    feature_vector_size: int = 63,
    input_shape: list[int] | None = None,
    output_shape: list[int] | None = None,
    vocab_path: Path | None = None,
) -> Path:
    """Create a standardized release bundle containing manifest.json, checksums, and model metadata."""
    ensure_dir(export_dir)

    if input_shape is None:
        input_shape = [1, feature_vector_size]
    if output_shape is None:
        output_shape = [1, 1]

    sha256_checksum = compute_sha256(tflite_path)

    artifacts = {
        "tflite": tflite_path.name,
    }

    if vocab_path and vocab_path.exists():
        vocab_dest = export_dir / vocab_path.name
        vocab_dest.write_bytes(vocab_path.read_bytes())
        artifacts["vocab"] = vocab_path.name

    manifest = {
        "model_name": model_name,
        "version": version,
        "schema_version": schema_version,
        "feature_vector_size": feature_vector_size,
        "sha256": sha256_checksum,
        "input_shape": input_shape,
        "output_shape": output_shape,
        "artifacts": artifacts,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    manifest_path = export_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    return manifest_path


def _representative_dataset(
    features: np.ndarray,
    max_samples: int = 256,
) -> Callable[[], object]:
    sample = features[:max_samples].astype(np.float32)

    def generate():
        for row in sample:
            yield [row.reshape(1, -1)]

    return generate

