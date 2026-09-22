from __future__ import annotations

import sys
from pathlib import Path

# Ensure attentionos-dataset is in sys.path
sys.path.insert(0, str(Path(__file__).parent.parent / "attentionos-dataset"))

import pytest
from generator.pii_sanitizer import PIISanitizer


def test_pii_sanitizer_emails():
    sanitizer = PIISanitizer()
    text = "Please reach out to john.doe@example.com or user.test@domain.org for info."
    cleaned = sanitizer.sanitize(text)
    assert "john.doe@example.com" not in cleaned
    assert "user.test@domain.org" not in cleaned
    assert "[REDACTED_EMAIL]" in cleaned


def test_pii_sanitizer_phone_numbers():
    sanitizer = PIISanitizer()
    text = "Call support at +1-800-555-0199 or 9876543210 immediately."
    cleaned = sanitizer.sanitize(text)
    assert "+1-800-555-0199" not in cleaned
    assert "9876543210" not in cleaned
    assert "[REDACTED_PHONE]" in cleaned


def test_pii_sanitizer_credit_cards():
    sanitizer = PIISanitizer()
    text = "Card 4532-1100-8890-2311 was charged."
    cleaned = sanitizer.sanitize(text)
    assert "4532-1100-8890-2311" not in cleaned
    assert "[REDACTED_CARD]" in cleaned


def test_pii_sanitizer_ssn():
    sanitizer = PIISanitizer()
    text = "Your SSN is 123-45-6789."
    cleaned = sanitizer.sanitize(text)
    assert "123-45-6789" not in cleaned
    assert "[REDACTED_SSN]" in cleaned


def test_pii_sanitizer_clean_text():
    sanitizer = PIISanitizer()
    text = "Meeting at 3 PM in Room 101."
    assert sanitizer.sanitize(text) == text


def test_pii_sanitizer_multiple():
    sanitizer = PIISanitizer()
    text = "Email me at user@test.com or call 555-123-4567 regarding card 4000123456789010."
    cleaned = sanitizer.sanitize(text)
    assert "user@test.com" not in cleaned
    assert "555-123-4567" not in cleaned
    assert "4000123456789010" not in cleaned
    assert "[REDACTED_EMAIL]" in cleaned
    assert "[REDACTED_PHONE]" in cleaned
    assert "[REDACTED_CARD]" in cleaned
