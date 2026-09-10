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


def create_model_bundle(
    bundle_dir: Path,
    version_tag: str,
    tflite_files: dict[str, Path],
    rules_path: Path | None = None,
) -> Path:
    """Package model binaries and rules into a versioned bundle with manifest.json and SHA-256 checksums."""
    ensure_dir(bundle_dir)
    files_manifest: dict[str, dict[str, object]] = {}

    for target_name, src_path in tflite_files.items():
        if src_path.exists():
            data = src_path.read_bytes()
            dst_path = bundle_dir / target_name
            dst_path.write_bytes(data)

            sha256_hash = hashlib.sha256(data).hexdigest()
            files_manifest[target_name] = {
                "sha256": sha256_hash,
                "size": len(data),
                "url": f"https://models.ghostai.local/{target_name}",
            }

    if rules_path and rules_path.exists():
        data = rules_path.read_bytes()
        dst_path = bundle_dir / "rules.json"
        dst_path.write_bytes(data)

        sha256_hash = hashlib.sha256(data).hexdigest()
        files_manifest["rules.json"] = {
            "sha256": sha256_hash,
            "size": len(data),
            "url": "https://models.ghostai.local/rules.json",
        }

    manifest = {
        "version": version_tag,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "files": files_manifest,
    }

    manifest_path = bundle_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return bundle_dir


def _representative_dataset(
    features: np.ndarray,
    max_samples: int = 256,
) -> Callable[[], object]:
    sample = features[:max_samples].astype(np.float32)

    def generate():
        for row in sample:
            yield [row.reshape(1, -1)]

    return generate

