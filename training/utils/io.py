"""JSON and filesystem helpers."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_sha256_sidecar(path: Path) -> Path:
    sidecar_path = path.parent / f"{path.name}.sha256"
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    sidecar_path.write_text(f"{digest}\n", encoding="utf-8")
    return sidecar_path


def verify_sha256_sidecar(path: Path) -> None:
    sidecar_path = path.parent / f"{path.name}.sha256"
    if not sidecar_path.exists():
        raise ValueError(f"Checksum sidecar missing for dataset: {sidecar_path}")

    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            hasher.update(chunk)
    computed = hasher.hexdigest().lower()

    content = sidecar_path.read_text(encoding="utf-8").strip()
    if not content:
        raise ValueError(f"Checksum sidecar file is empty: {sidecar_path}")
    expected = content.split()[0].lower()

    if computed != expected:
        raise ValueError(f"Checksum mismatch for dataset {path}: expected {expected}, got {computed}")


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise FileNotFoundError(f"Dataset not found: {path}")

    verify_sha256_sidecar(path)

    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                value = json.loads(stripped)
            except json.JSONDecodeError as exc:
                raise ValueError(f"Invalid JSON on line {line_number}: {exc}") from exc
            if not isinstance(value, dict):
                raise ValueError(f"Line {line_number} must contain a JSON object.")
            records.append(value)

    if not records:
        raise ValueError(f"Dataset is empty: {path}")
    return records


def write_json(path: Path, value: Any) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
    write_sha256_sidecar(path)


def write_lines(path: Path, lines: Iterable[str]) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as handle:
        for line in lines:
            handle.write(line.rstrip())
            handle.write("\n")

