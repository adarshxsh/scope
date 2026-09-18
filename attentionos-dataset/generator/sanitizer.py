from __future__ import annotations

import re
from typing import Any

# Pattern for control characters (excluding standard whitespace)
CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")

# System/Prompt Injection delimiters and dangerous instruction phrases
INJECTION_PATTERNS = [
    (re.compile(r"\[/?INST\]", re.IGNORECASE), "[filtered_tag]"),
    (re.compile(r"<\|im_start\|>", re.IGNORECASE), "[filtered_tag]"),
    (re.compile(r"<\|im_end\|>", re.IGNORECASE), "[filtered_tag]"),
    (re.compile(r"```[a-z]*", re.IGNORECASE), ""),
    (re.compile(r"^(system|user|assistant)\s*:", re.IGNORECASE | re.MULTILINE), r"\1_text:"),
    (re.compile(r"ignore\s+(previous|above)\s+instructions?", re.IGNORECASE), "follow instructions"),
    (re.compile(r"forget\s+(previous|above)\s+instructions?", re.IGNORECASE), "follow instructions"),
    (re.compile(r"disregard\s+(previous|above)\s+instructions?", re.IGNORECASE), "follow instructions"),
    (re.compile(r"override\s+system\s+prompt", re.IGNORECASE), "system policy"),
]

# PII Patterns for Safe Logging
EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
PHONE_RE = re.compile(r"\+?\d[\d\s\-\(\)]{7,15}\d")
OTP_RE = re.compile(r"\b\d{4,8}\b")
MONEY_RE = re.compile(r"₹\s*\d+(?:,\d+)*(?:\.\d+)?")


def sanitize_prompt_input(val: Any) -> str:
    """Sanitizes an input value to prevent prompt template injection."""
    if val is None:
        return ""
    text = str(val)

    # Remove non-printable control characters
    text = CONTROL_CHARS_RE.sub("", text)

    # Neutralize prompt injection patterns
    for pattern, replacement in INJECTION_PATTERNS:
        text = pattern.sub(replacement, text)

    # Normalize whitespace (replace newlines and tabs with spaces to keep structural prompt boundaries)
    text = re.sub(r"[\r\n\t]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()

    return text


def sanitize_context(ctx: dict[str, Any]) -> dict[str, Any]:
    """Recursively sanitizes context dictionary values."""
    sanitized: dict[str, Any] = {}
    for key, val in ctx.items():
        if isinstance(val, dict):
            sanitized[key] = sanitize_context(val)
        elif isinstance(val, list):
            sanitized[key] = [
                sanitize_prompt_input(item) if isinstance(item, str) else item
                for item in val
            ]
        elif isinstance(val, str):
            sanitized[key] = sanitize_prompt_input(val)
        else:
            sanitized[key] = val
    return sanitized


def redact_pii(text: str) -> str:
    """Redacts PII patterns from text for diagnostic logging."""
    if not text:
        return ""
    redacted = EMAIL_RE.sub("[EMAIL_REDACTED]", text)
    redacted = MONEY_RE.sub("[MONEY_REDACTED]", redacted)
    redacted = PHONE_RE.sub("[PHONE_REDACTED]", redacted)
    return redacted


def validate_and_clean_output(title: str, body: str) -> tuple[str, str] | None:
    """Validates generated title and body, stripping markdown/injection artifacts."""
    if not isinstance(title, str) or not isinstance(body, str):
        return None

    # Strip markdown wrappers, quotes, code blocks, control characters
    clean_title = CONTROL_CHARS_RE.sub("", title)
    clean_body = CONTROL_CHARS_RE.sub("", body)

    clean_title = re.sub(r"^[`'\"]+|[`'\"]+$", "", clean_title).strip()
    clean_body = re.sub(r"^[`'\"]+|[`'\"]+$", "", clean_body).strip()

    clean_title = " ".join(clean_title.split())
    clean_body = " ".join(clean_body.split())

    # Verify length and non-emptiness constraints
    if not clean_title or not clean_body:
        return None
    if len(clean_title) > 50 or len(clean_body) > 140:
        return None

    # Check for residual prompt injection tokens in output
    low_title = clean_title.lower()
    low_body = clean_body.lower()
    for pattern in ["ignore previous", "system:", "<|im_start|>", "return only json"]:
        if pattern in low_title or pattern in low_body:
            return None

    return clean_title, clean_body
