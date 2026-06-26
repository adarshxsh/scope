from __future__ import annotations

from collections import Counter
from typing import Iterable


def summarize(records: Iterable[dict]) -> dict:
    total = 0
    categories: Counter[str] = Counter()
    priorities: Counter[str] = Counter()
    intents: Counter[str] = Counter()
    look_again = 0
    for record in records:
        total += 1
        categories[record["category"]] += 1
        priorities[record["priority"]] += 1
        intents[record["intent"]] += 1
        look_again += int(record["look_again"])
    return {
        "total": total,
        "categories": dict(categories.most_common()),
        "priorities": dict(priorities.most_common()),
        "intents": dict(intents.most_common()),
        "look_again": look_again,
    }
