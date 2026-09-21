"""JSON and filesystem helpers."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable


from training.dataset.loader import load_jsonl_dataset


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_jsonl(path: Path, strict_verify: bool = False) -> list[dict[str, Any]]:
    return load_jsonl_dataset(path, strict_verify=strict_verify)


def write_json(path: Path, value: Any) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def write_lines(path: Path, lines: Iterable[str]) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as handle:
        for line in lines:
            handle.write(line.rstrip())
            handle.write("\n")

