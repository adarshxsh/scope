from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

from export.pii import process_record_privacy


def write_jsonl(
    path: Path,
    records: Iterable[dict],
    redact_pii: bool = True,
    perturb_scores: bool = True,
    epsilon: float = 1.0,
) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            if redact_pii or perturb_scores:
                record = process_record_privacy(
                    record,
                    redact_pii=redact_pii,
                    perturb_scores=perturb_scores,
                    epsilon=epsilon,
                )
            handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
            handle.write("\n")
            count += 1
    return count
