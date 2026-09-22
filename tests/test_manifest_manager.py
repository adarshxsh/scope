from __future__ import annotations

import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "training"))
sys.path.insert(0, str(Path(__file__).parent.parent / "attentionos-dataset"))

import pytest
from manifest_manager import ManifestManager, ManifestValidationError


def test_create_and_validate_manifest(tmp_path: Path):
    artifact = tmp_path / "data.jsonl"
    artifact.write_text('{"id": 1, "title": "Test"}\n{"id": 2, "title": "Sample"}\n', encoding="utf-8")

    manifest_path = ManifestManager.create_manifest(
        artifact_path=artifact,
        artifact_type="dataset",
        record_count=2,
        seed=42,
    )

    assert manifest_path.exists()

    validated = ManifestManager.validate_manifest(
        artifact_path=artifact,
        expected_record_count=2,
        strict=True,
    )
    assert validated["sha256"] == ManifestManager.calculate_sha256(artifact)
    assert validated["record_count"] == 2


def test_tampered_artifact_raises_validation_error(tmp_path: Path):
    artifact = tmp_path / "data.jsonl"
    artifact.write_text('{"id": 1, "title": "Original"}\n', encoding="utf-8")

    manifest_path = ManifestManager.create_manifest(
        artifact_path=artifact,
        artifact_type="dataset",
        record_count=1,
    )

    # Modify artifact content
    artifact.write_text('{"id": 1, "title": "Tampered"}\n', encoding="utf-8")

    with pytest.raises(ManifestValidationError) as excinfo:
        ManifestManager.validate_manifest(artifact, strict=True)
    assert "digest mismatch" in str(excinfo.value).lower()


def test_mismatched_record_count_raises_validation_error(tmp_path: Path):
    artifact = tmp_path / "data.jsonl"
    artifact.write_text('{"id": 1}\n{"id": 2}\n', encoding="utf-8")

    ManifestManager.create_manifest(
        artifact_path=artifact,
        artifact_type="dataset",
        record_count=2,
    )

    with pytest.raises(ManifestValidationError) as excinfo:
        ManifestManager.validate_manifest(artifact, expected_record_count=5, strict=True)
    assert "record count mismatch" in str(excinfo.value).lower()


def test_missing_manifest_strict_raises_error(tmp_path: Path):
    artifact = tmp_path / "unmanifested.jsonl"
    artifact.write_text('{"id": 1}\n', encoding="utf-8")

    with pytest.raises(ManifestValidationError) as excinfo:
        ManifestManager.validate_manifest(artifact, strict=True)
    assert "missing" in str(excinfo.value).lower()


def test_missing_manifest_dev_mode_issues_warning(tmp_path: Path):
    artifact = tmp_path / "unmanifested.jsonl"
    artifact.write_text('{"id": 1}\n', encoding="utf-8")

    with pytest.warns(UserWarning, match="missing"):
        result = ManifestManager.validate_manifest(artifact, strict=False)
        assert result == {}
