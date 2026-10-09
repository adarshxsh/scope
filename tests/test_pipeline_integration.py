from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
from training.dataset.loader import load_jsonl_dataset
from training.manifest_manager import ManifestManager, ManifestValidationError


def test_generator_export_and_loader(tmp_path: Path):
    output_path = tmp_path / "test_notifications.jsonl"

    # Run generate.py via subprocess or direct import
    cmd = [
        sys.executable,
        str(Path(__file__).parent.parent / "attentionos-dataset" / "generate.py"),
        "--count", "100",
        "--seed", "123",
        "--output", str(output_path),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0, f"generate.py failed: {res.stderr}"

    manifest_path = ManifestManager.get_manifest_path(output_path)
    assert manifest_path.exists(), "Manifest file was not created by generate.py"

    # Load dataset with loader
    records = load_jsonl_dataset(output_path, strict=True)
    assert len(records) == 100

    # Tamper with dataset file
    with output_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps({"id": "tampered", "title": "bad"}) + "\n")

    with pytest.raises(ManifestValidationError):
        load_jsonl_dataset(output_path, strict=True)
