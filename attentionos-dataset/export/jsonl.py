from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


def write_jsonl(path: Path, records: Iterable[dict]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
            handle.write("\n")
            count += 1

    # Compute cryptographic SHA-256 digest of the exported JSONL dataset
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(65536):
            hasher.update(chunk)
    digest = hasher.hexdigest()

    # Write companion .sha256 sidecar digest file
    sha256_path = path.parent / f"{path.name}.sha256"
    sha256_path.write_text(f"{digest}\n", encoding="utf-8")

    # Write companion manifest metadata files
    manifest_data = {
        "file_name": path.name,
        "file_size": path.stat().st_size,
        "sample_count": count,
        "sha256": digest,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    manifest_named_path = path.parent / f"{path.name}.manifest.json"
    manifest_named_path.write_text(json.dumps(manifest_data, indent=2), encoding="utf-8")

    manifest_default_path = path.parent / "manifest.json"
    manifest_default_path.write_text(json.dumps(manifest_data, indent=2), encoding="utf-8")

    return count
