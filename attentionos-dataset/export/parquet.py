from __future__ import annotations

from pathlib import Path
from typing import Iterable


def write_parquet(path: Path, records: Iterable[dict]) -> int:
    raise RuntimeError(
        "Parquet export needs pyarrow or pandas, which are intentionally not required. "
        f"Use JSONL/CSV, or add your own parquet writer for {path}."
    )
