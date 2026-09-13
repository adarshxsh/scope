from __future__ import annotations

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
    "review_score",
    "labels",
}


def validate_record(record: dict) -> list[str]:
    errors: list[str] = []
    missing = REQUIRED_FIELDS.difference(record)
    if missing:
        errors.append(f"missing fields: {sorted(missing)}")
    if len(record.get("title", "")) > 50:
        errors.append("title exceeds 50 characters")
    if len(record.get("body", "")) > 140:
        errors.append("body exceeds 140 characters")
    if not isinstance(record.get("android", {}), dict):
        errors.append("android must be an object")
    score = record.get("priority_score")
    if not isinstance(score, (int, float)) or score < 0 or score > 100:
        errors.append("priority_score must be a number in 0..100")
    review_score = record.get("review_score")
    if not isinstance(review_score, (int, float)) or review_score < 0 or review_score > 100:
        errors.append("review_score must be a number in 0..100")
    return errors
