from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Iterable


FIELDNAMES = [
    "id",
    "app_name",
    "package_name",
    "category",
    "subcategory",
    "notification_type",
    "title",
    "body",
    "intent",
    "requires_action",
    "urgency",
    "priority_score",
    "priority",
    "look_again_score",
    "look_again",
    "entities",
    "android",
]


def write_csv(path: Path, records: Iterable[dict]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, extrasaction="ignore")
        writer.writeheader()
        for record in records:
            row = dict(record)
            row["entities"] = json.dumps(row.get("entities", {}), ensure_ascii=False)
            row["android"] = json.dumps(row.get("android", {}), ensure_ascii=False)
            writer.writerow(row)
            count += 1
    return count
