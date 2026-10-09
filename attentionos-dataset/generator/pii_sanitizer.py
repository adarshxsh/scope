from __future__ import annotations

import re


class PIISanitizer:
    """Utility to detect and sanitize Personally Identifiable Information (PII) from text."""

    def __init__(self) -> None:
        # Regex patterns for sensitive entity types
        self.email_pattern = re.compile(
            r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"
        )
        self.phone_pattern = re.compile(
            r"\b(?:\+\d{1,3}[- ]?)?\(?\d{3}\)?[- ]?\d{3}[- ]?\d{4}\b|\b\d{10}\b"
        )
        self.card_pattern = re.compile(
            r"\b(?:\d[ -]*?){13,19}\b"
        )
        self.ssn_pattern = re.compile(
            r"\b\d{3}-\d{2}-\d{4}\b"
        )

    def sanitize(self, text: str) -> str:
        if not text:
            return ""

        result = text
        # Order matters: SSN & Card before general numbers if needed, but patterns are distinct
        result = self.email_pattern.sub("[REDACTED_EMAIL]", result)
        result = self.phone_pattern.sub("[REDACTED_PHONE]", result)
        result = self.card_pattern.sub("[REDACTED_CARD]", result)
        result = self.ssn_pattern.sub("[REDACTED_SSN]", result)
        return result
