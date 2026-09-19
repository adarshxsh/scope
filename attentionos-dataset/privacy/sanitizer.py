from __future__ import annotations

import logging
import re
from typing import Any

logger = logging.getLogger(__name__)

# Regular expressions for PII detection and sanitization
_EMAIL_REGEX = re.compile(
    r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b", re.IGNORECASE
)
_PHONE_REGEX = re.compile(
    r"\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b|\b1800[-.\s]?[A-Z0-9]{3,4}[-.\s]?[A-Z0-9]{4}\b",
    re.IGNORECASE,
)
_URL_REGEX = re.compile(r"\b(?:https?://|www\.)[^\s]+", re.IGNORECASE)

_ORDER_ID_REGEX = re.compile(
    r"\b(?:OD|ORD|order|ord)[\s#:.-]*[A-Z0-9-]{4,}\b", re.IGNORECASE
)
_REF_ID_REGEX = re.compile(
    r"\b(?:UPI ref|ref|reference|pnr|txn|txnid|utr)[\s#:.-]*[A-Z0-9-]{4,}\b",
    re.IGNORECASE,
)
_ACCOUNT_LAST4_REGEX = re.compile(
    r"\b(?:ending|A/c|account)[\s#:.-]*\d{4}\b", re.IGNORECASE
)
_TICKET_REGEX = re.compile(r"\bATT-\d{3,5}\b", re.IGNORECASE)

_MONEY_AMOUNT_REGEX = re.compile(
    r"(?:₹|rs\.?|inr|usd|\$|eur|€|gbp|£|aed)\s*([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)",
    re.IGNORECASE,
)

_OTP_CONTEXT_REGEX = re.compile(
    r"(?:otp|code|verification|verify|pin|password|2fa)[\s:#.-]*(\b\d{4,8}\b)|(\b\d{4,8}\b)[\s:#.-]*(?:is your|to verify|valid for)",
    re.IGNORECASE,
)

_NAME_CONTEXT_PATTERNS = [
    re.compile(r"\bfrom\s+([A-Z][a-z]+)\b"),
    re.compile(r"\bwith\s+([A-Z][a-z]+)\b"),
    re.compile(r"\bby\s+([A-Z][a-z]+)\b"),
    re.compile(r"\bDr\.\s+([A-Z][a-z]+)\b"),
    re.compile(r"\b([A-Z][a-z]+)\s+(?:paid|requested|sent|commented|reacted|assigned|mentioned)\b"),
]


class PrivacySanitizer:
    """Post-processing privacy sanitization layer for synthetic dataset records."""

    def __init__(self) -> None:
        pass

    def sanitize_text(self, text: str | None, ctx: dict[str, Any] | None = None) -> str:
        """Sanitizes sensitive PII structures in cleartext strings."""
        if not text:
            return ""

        try:
            sanitized = str(text)

            # 1. Context-based replacements if generation context is supplied
            if ctx:
                for key in ("person", "doctor", "sender"):
                    val = ctx.get(key)
                    if val and isinstance(val, str) and len(val) > 1:
                        sanitized = re.sub(
                            r"\b" + re.escape(str(val)) + r"\b",
                            "[NAME]",
                            sanitized,
                            flags=re.IGNORECASE,
                        )

                for key in ("email",):
                    val = ctx.get(key)
                    if val and isinstance(val, str):
                        sanitized = sanitized.replace(str(val), "[EMAIL]")

                for key in ("otp",):
                    val = ctx.get(key)
                    if val and isinstance(val, (str, int)):
                        sanitized = re.sub(
                            r"\b" + re.escape(str(val)) + r"\b",
                            "[OTP]",
                            sanitized,
                        )

                for key in ("order_id",):
                    val = ctx.get(key)
                    if val and isinstance(val, str):
                        sanitized = sanitized.replace(str(val), "[ORDER_ID]")

                for key in ("ref",):
                    val = ctx.get(key)
                    if val and isinstance(val, (str, int)):
                        sanitized = re.sub(
                            r"\b" + re.escape(str(val)) + r"\b",
                            "[REF_ID]",
                            sanitized,
                        )

                for key in ("ticket",):
                    val = ctx.get(key)
                    if val and isinstance(val, str):
                        sanitized = sanitized.replace(str(val), "[TICKET_ID]")

            # 2. General regex-based PII replacements
            sanitized = _EMAIL_REGEX.sub("[EMAIL]", sanitized)
            sanitized = _PHONE_REGEX.sub("[PHONE]", sanitized)
            sanitized = _URL_REGEX.sub("[URL]", sanitized)

            sanitized = _ORDER_ID_REGEX.sub("[ORDER_ID]", sanitized)
            sanitized = _REF_ID_REGEX.sub("[REF_ID]", sanitized)
            sanitized = _ACCOUNT_LAST4_REGEX.sub("ending [CARD_LAST4]", sanitized)
            sanitized = _TICKET_REGEX.sub("[TICKET_ID]", sanitized)

            # Monetary amounts (e.g., ₹15499 -> ₹[AMOUNT])
            sanitized = _MONEY_AMOUNT_REGEX.sub("₹[AMOUNT]", sanitized)

            # OTPs in context
            def _otp_replacer(match: re.Match) -> str:
                full_text = match.group(0)
                return re.sub(r"\b\d{4,8}\b", "[OTP]", full_text)

            sanitized = _OTP_CONTEXT_REGEX.sub(_otp_replacer, sanitized)

            # Generic name patterns
            for pattern in _NAME_CONTEXT_PATTERNS:
                def _name_replacer(m: re.Match) -> str:
                    full = m.group(0)
                    name_group = m.group(1)
                    return full.replace(name_group, "[NAME]")

                sanitized = pattern.sub(_name_replacer, sanitized)

            return sanitized
        except Exception as err:
            logger.warning(f"Error during text sanitization, returning fallback: {err}")
            return _EMAIL_REGEX.sub("[EMAIL]", str(text) if text is not None else "")

    def sanitize_entities(
        self, entities: dict[str, Any] | None, ctx: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Sanitizes entity key-values dictionary."""
        if not isinstance(entities, dict):
            return {}

        try:
            sanitized: dict[str, Any] = dict(entities)

            if "amount" in sanitized:
                sanitized["amount"] = "[AMOUNT]"

            if "reference_id" in sanitized:
                sanitized["reference_id"] = "[REF_ID]"

            for key, val in list(sanitized.items()):
                if isinstance(val, str):
                    sanitized[key] = self.sanitize_text(val, ctx=ctx)

            return sanitized
        except Exception as err:
            logger.warning(f"Error during entities sanitization: {err}")
            return {"sanitization_fallback": True}

    def sanitize_record(
        self, record: dict[str, Any] | None, ctx: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Sanitizes a full notification record."""
        if not isinstance(record, dict):
            return {}

        try:
            sanitized_record = dict(record)

            if "title" in sanitized_record:
                sanitized_record["title"] = self.sanitize_text(
                    sanitized_record["title"], ctx=ctx
                )

            if "body" in sanitized_record:
                sanitized_record["body"] = self.sanitize_text(
                    sanitized_record["body"], ctx=ctx
                )

            if "entities" in sanitized_record and isinstance(
                sanitized_record["entities"], dict
            ):
                sanitized_record["entities"] = self.sanitize_entities(
                    sanitized_record["entities"], ctx=ctx
                )

            sanitized_record["privacy_sanitized"] = True
            return sanitized_record
        except Exception as err:
            logger.error(f"Failed to sanitize record: {err}")
            fallback_record = dict(record) if record else {}
            fallback_record["title"] = self.sanitize_text(record.get("title") if record else "")
            fallback_record["body"] = self.sanitize_text(record.get("body") if record else "")
            fallback_record["privacy_sanitized"] = True
            return fallback_record
