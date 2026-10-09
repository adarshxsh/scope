from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable


def write_sha256_sidecar(path: Path) -> Path:
    sidecar_path = path.parent / f"{path.name}.sha256"
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    sidecar_path.write_text(f"{digest}\n", encoding="utf-8")
    return sidecar_path


def write_jsonl(path: Path, records: Iterable[dict]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
            handle.write("\n")
            count += 1
    write_sha256_sidecar(path)
    return count
