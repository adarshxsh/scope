from __future__ import annotations

import hashlib
import json
import warnings
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class ManifestValidationError(Exception):
    """Raised when an artifact manifest is missing, corrupt, or fails validation."""

    pass


class ManifestManager:
    """Manager for generating and validating artifact cryptographic manifests."""

    @staticmethod
    def calculate_sha256(filepath: Path) -> str:
        """Calculates the SHA-256 hex digest of a file."""
        if not filepath.exists():
            raise FileNotFoundError(f"File not found: {filepath}")
        sha256_hash = hashlib.sha256()
        with open(filepath, "rb") as f:
            for byte_block in iter(lambda: f.read(65536), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()

    @staticmethod
    def get_schema_hash(schema_path: Path | None = None) -> str:
        """Computes SHA-256 hash of the schema file."""
        if schema_path is None:
            possible_path = Path(__file__).parent / "schema" / "notification_schema.json"
            if not possible_path.exists():
                possible_path = Path("attentionos-dataset/schema/notification_schema.json")
            schema_path = possible_path

        if schema_path and schema_path.exists():
            return ManifestManager.calculate_sha256(schema_path)
        return ""

    @staticmethod
    def get_manifest_path(artifact_path: Path) -> Path:
        """Returns the manifest file path for a given artifact path."""
        alt1 = Path(str(artifact_path) + ".manifest.json")
        if alt1.exists():
            return alt1
        alt2 = artifact_path.with_suffix(".manifest.json")
        if alt2.exists():
            return alt2

        if artifact_path.suffix.lower() == ".tflite":
            return alt1
        return alt2

    @classmethod
    def create_manifest(
        cls,
        artifact_path: Path,
        artifact_type: str = "dataset",
        record_count: int | None = None,
        seed: int | None = None,
        generator_config: dict[str, Any] | None = None,
        dataset_sha256: str | None = None,
        schema_path: Path | None = None,
        manifest_path: Path | None = None,
    ) -> Path:
        """Generates and writes a structured JSON manifest file for an artifact."""
        if not artifact_path.exists():
            raise FileNotFoundError(f"Artifact not found: {artifact_path}")

        sha256_digest = cls.calculate_sha256(artifact_path)
        file_size_bytes = artifact_path.stat().st_size
        schema_hash = cls.get_schema_hash(schema_path)

        if manifest_path is None:
            manifest_path = cls.get_manifest_path(artifact_path)

        config = dict(generator_config or {})
        if seed is not None and "seed" not in config:
            config["seed"] = seed
        if dataset_sha256 is not None:
            config["dataset_sha256"] = dataset_sha256

        manifest_data: dict[str, Any] = {
            "artifact_path": str(artifact_path.name),
            "artifact_type": artifact_type,
            "sha256": sha256_digest,
            "file_size_bytes": file_size_bytes,
            "record_count": record_count,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "schema_hash": schema_hash,
            "generator_config": config,
        }

        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        with manifest_path.open("w", encoding="utf-8") as f:
            json.dump(manifest_data, f, indent=2, sort_keys=True)
            f.write("\n")

        return manifest_path

    @classmethod
    def validate_manifest(
        cls,
        artifact_path: Path,
        expected_record_count: int | None = None,
        expected_schema_hash: str | None = None,
        strict: bool = True,
        manifest_path: Path | None = None,
    ) -> dict[str, Any]:
        """Validates an artifact against its manifest file."""
        if not artifact_path.exists():
            raise FileNotFoundError(f"Artifact file not found: {artifact_path}")

        if manifest_path is None:
            manifest_path = cls.get_manifest_path(artifact_path)

        if not manifest_path.exists():
            msg = f"Manifest file missing for {artifact_path} at {manifest_path}"
            if strict:
                raise ManifestValidationError(msg)
            else:
                warnings.warn(msg, UserWarning)
                return {}

        try:
            with manifest_path.open("r", encoding="utf-8") as f:
                manifest_data = json.load(f)
        except Exception as exc:
            raise ManifestValidationError(f"Corrupt manifest file at {manifest_path}: {exc}") from exc

        # Recalculate file hash
        current_sha256 = cls.calculate_sha256(artifact_path)
        expected_sha256 = manifest_data.get("sha256")

        if current_sha256 != expected_sha256:
            raise ManifestValidationError(
                f"SHA-256 digest mismatch for {artifact_path}. "
                f"Expected: {expected_sha256}, Calculated: {current_sha256}"
            )

        manifest_record_count = manifest_data.get("record_count")
        if expected_record_count is not None and manifest_record_count is not None:
            if expected_record_count != manifest_record_count:
                raise ManifestValidationError(
                    f"Record count mismatch for {artifact_path}. "
                    f"Expected: {expected_record_count}, Manifest: {manifest_record_count}"
                )

        manifest_schema_hash = manifest_data.get("schema_hash")
        if expected_schema_hash is not None and manifest_schema_hash is not None and manifest_schema_hash != "":
            if expected_schema_hash != manifest_schema_hash:
                raise ManifestValidationError(
                    f"Schema hash mismatch for {artifact_path}. "
                    f"Expected: {expected_schema_hash}, Manifest: {manifest_schema_hash}"
                )

        return manifest_data
