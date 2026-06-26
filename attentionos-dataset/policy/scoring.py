from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


CRITICAL_TYPES = {
    "otp",
    "security_alert",
    "fraud_alert",
    "emergency_alert",
    "payment_failed",
    "password_reset",
}

ACTION_INTENTS = {
    "verify",
    "approve",
    "pay",
    "join",
    "submit",
    "review",
    "respond",
    "reset",
    "track",
}

PROMO_TYPES = {
    "promotion",
    "coupon",
    "cashback",
    "flash_sale",
    "recommendation",
}


def _deadline_boost(deadline: str | None, now: datetime) -> int:
    if not deadline:
        return 0
    try:
        due = datetime.fromisoformat(deadline.replace("Z", "+00:00"))
    except ValueError:
        return 0
    if due.tzinfo is None:
        due = due.replace(tzinfo=timezone.utc)
    hours = (due - now).total_seconds() / 3600
    if hours < 0:
        return 16
    if hours <= 1:
        return 26
    if hours <= 6:
        return 20
    if hours <= 24:
        return 14
    if hours <= 72:
        return 7
    return 2


def _bucket(score: int) -> str:
    if score >= 82:
        return "critical"
    if score >= 62:
        return "high"
    if score >= 34:
        return "medium"
    return "low"


def score_notification(record: dict[str, Any], now: datetime | None = None) -> dict[str, Any]:
    """Deterministic policy engine for AttentionOS training labels."""
    now = now or datetime.now(timezone.utc)
    android = record.get("android", {})
    notification_type = record.get("notification_type", "")
    intent = record.get("intent", "")
    category = record.get("category", "")

    score = 8
    reasons: list[str] = []

    importance = int(android.get("importance", 3))
    score += max(0, min(5, importance)) * 5
    reasons.append(f"android_importance={importance}")

    if notification_type in CRITICAL_TYPES:
        score += 35
        reasons.append(f"type={notification_type}")
    if category in {"Emergency Alerts", "Security", "Authentication", "OTP"}:
        score += 18
        reasons.append(f"category={category}")
    if record.get("requires_action"):
        score += 18
        reasons.append("requires_action")
    if intent in ACTION_INTENTS:
        score += 12
        reasons.append(f"intent={intent}")
    if record.get("contains_otp"):
        score += 22
        reasons.append("contains_otp")
    if record.get("contains_money"):
        amount = float(record.get("entities", {}).get("amount", 0) or 0)
        score += 9 if amount < 5000 else 17
        reasons.append("contains_money")
    if record.get("contains_date") or record.get("contains_time"):
        score += 5
        reasons.append("time_sensitive")

    deadline_points = _deadline_boost(record.get("deadline"), now)
    if deadline_points:
        score += deadline_points
        reasons.append(f"deadline_boost={deadline_points}")

    if notification_type in PROMO_TYPES:
        score -= 24
        reasons.append("promotional")
    if record.get("is_recurring") and not record.get("requires_action"):
        score -= 7
        reasons.append("passive_recurring")
    if android.get("ongoing") and not record.get("requires_action"):
        score -= 5
        reasons.append("ongoing_passive")

    score = max(0, min(100, score))
    priority = _bucket(score)
    look_again_score = score
    if record.get("requires_action"):
        look_again_score += 10
    if record.get("deadline"):
        look_again_score += 8
    if notification_type in PROMO_TYPES:
        look_again_score -= 18
    look_again_score = max(0, min(100, look_again_score))

    return {
        "priority_score": score,
        "priority": priority,
        "priority_reason": "; ".join(reasons),
        "urgency": priority,
        "look_again_score": look_again_score,
        "look_again": look_again_score >= 55,
    }
