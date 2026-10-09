import hashlib
import json
import tempfile
import warnings
from pathlib import Path

import pytest
from training.dataset.loader import (
    compute_file_sha256,
    load_jsonl_dataset,
    verify_dataset_hash,
)
from training.train import compute_path_sha256


def test_load_jsonl_dataset_valid_hash():
    records = [{"id": "1", "val": "a"}, {"id": "2", "val": "b"}]
    with tempfile.TemporaryDirectory() as tmp_dir:
        dataset_path = Path(tmp_dir) / "test.jsonl"
        lines = [json.dumps(r) for r in records]
        dataset_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        digest = compute_file_sha256(dataset_path)
        sidecar_path = Path(tmp_dir) / "test.jsonl.sha256"
        sidecar_path.write_text(f"{digest}\n", encoding="utf-8")

        loaded = load_jsonl_dataset(dataset_path)
        assert len(loaded) == 2
        assert loaded[0]["id"] == "1"


def test_load_jsonl_dataset_tampered_hash_raises_value_error():
    records = [{"id": "1", "val": "a"}]
    with tempfile.TemporaryDirectory() as tmp_dir:
        dataset_path = Path(tmp_dir) / "test.jsonl"
        lines = [json.dumps(r) for r in records]
        dataset_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        # Write wrong hash
        sidecar_path = Path(tmp_dir) / "test.jsonl.sha256"
        sidecar_path.write_text("0" * 64 + "\n", encoding="utf-8")

        with pytest.raises(ValueError, match="SHA-256 digest mismatch"):
            load_jsonl_dataset(dataset_path)


def test_load_jsonl_dataset_missing_hash_behavior():
    records = [{"id": "1", "val": "a"}]
    with tempfile.TemporaryDirectory() as tmp_dir:
        dataset_path = Path(tmp_dir) / "test.jsonl"
        lines = [json.dumps(r) for r in records]
        dataset_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        # Without strict_verify, should warn and load
        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            loaded = load_jsonl_dataset(dataset_path, strict_verify=False)
            assert len(loaded) == 1
            assert any("No SHA-256 digest or manifest file found" in str(item.message) for item in w)

        # With strict_verify=True, should raise ValueError
        with pytest.raises(ValueError, match="No SHA-256 digest or manifest file found"):
            load_jsonl_dataset(dataset_path, strict_verify=True)


def test_compute_path_sha256_file_and_dir():
    with tempfile.TemporaryDirectory() as tmp_dir:
        file_path = Path(tmp_dir) / "sample.txt"
        file_path.write_text("hello world\n", encoding="utf-8")

        expected_file_hash = hashlib.sha256(b"hello world\n").hexdigest()
        assert compute_path_sha256(file_path) == expected_file_hash

        dir_path = Path(tmp_dir) / "sample_dir"
        dir_path.mkdir()
        (dir_path / "a.txt").write_text("content a", encoding="utf-8")
        dir_hash = compute_path_sha256(dir_path)
        assert len(dir_hash) == 64
