from __future__ import annotations

import re
from typing import Any

# Leak detection patterns
_RAW_EMAIL_PAT = re.compile(
    r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", re.IGNORECASE
)
_RAW_ORDER_ID_PAT = re.compile(
    r"\b(?:OD\d{6}|ORD\d{6}|Order\s*#\d{5,8})\b", re.IGNORECASE
)
_RAW_OTP_CONTEXT_PAT = re.compile(
    r"(?:otp|verification code|use)\s+(\b\d{4,8}\b)", re.IGNORECASE
)
_RAW_MONEY_PAT = re.compile(
    r"(?:₹|rs\.?|inr|\$)\s*[1-9]\d{2,6}(?!\s*\[AMOUNT\])", re.IGNORECASE
)


def check_privacy_leaks(record: dict[str, Any]) -> list[str]:
    """Scans a dataset record for un-sanitized PII leaks or schema violations."""
    errors: list[str] = []
    title = str(record.get("title", ""))
    body = str(record.get("body", ""))
    combined = f"{title} {body}"

    if _RAW_EMAIL_PAT.search(combined):
        errors.append("contains raw email address")

    if _RAW_ORDER_ID_PAT.search(combined):
        errors.append("contains unmasked order ID")

    if _RAW_OTP_CONTEXT_PAT.search(combined):
        errors.append("contains raw numeric OTP code")

    if _RAW_MONEY_PAT.search(combined):
        errors.append("contains raw unquantized monetary amount")

    entities = record.get("entities")
    if isinstance(entities, dict):
        if "amount" in entities and isinstance(entities["amount"], (int, float)):
            errors.append("entities contains raw numeric amount")

    return errors
