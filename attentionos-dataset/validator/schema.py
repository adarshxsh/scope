from __future__ import annotations

import re

CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")

REQUIRED_FIELDS = {
    "id",
    "app_name",
    "package_name",
    "category",
    "subcategory",
    "notification_type",
    "title",
    "body",
    "language",
    "requires_action",
    "intent",
    "android",
    "priority_score",
    "priority",
    "look_again_score",
    "look_again",
    "labels",
}


def validate_record(record: dict) -> list[str]:
    errors: list[str] = []
    missing = REQUIRED_FIELDS.difference(record)
    if missing:
        errors.append(f"missing fields: {sorted(missing)}")
    title = str(record.get("title", ""))
    body = str(record.get("body", ""))
    if len(title) > 50:
        errors.append("title exceeds 50 characters")
    if len(body) > 140:
        errors.append("body exceeds 140 characters")
    if not isinstance(record.get("android", {}), dict):
        errors.append("android must be an object")
    score = record.get("priority_score")
    if not isinstance(score, int) or score < 0 or score > 100:
        errors.append("priority_score must be an integer in 0..100")

    if CONTROL_CHARS_RE.search(title) or CONTROL_CHARS_RE.search(body):
        errors.append("title or body contains unescaped control characters")

    low_combined = f"{title} {body}".lower()
    for artifact in ["<|im_start|>", "[/inst]", "ignore previous instructions"]:
        if artifact in low_combined:
            errors.append(f"record contains prompt injection artifact: {artifact}")

    return errors

