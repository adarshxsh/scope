from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger("attentionos.privacy")

# Safe reserved domains under RFC 2606 and local test setups
SAFE_DOMAINS = {"example.com", "example.org", "example.net", "test.com", "local.test"}

# Regex definitions for PII and sensitive data patterns
EMAIL_REGEX = re.compile(r"\b([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b")
PHONE_REGEX = re.compile(
    r"\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b|\b[6-9]\d{9}\b"
)
CARD_REGEX = re.compile(
    r"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12}|(?:[0-9]{4}[- ]){3}[0-9]{4})\b"
)
CREDENTIAL_REGEX = re.compile(
    r"(?i)\b(password|passwd|passcode|pwd|secret|api[_\-]?key|auth[_\-]?token|bearer[_\-]?token)\s*(?:[:=]|\bis\b)?\s*([^\s,;]+)"
)
JWT_REGEX = re.compile(r"(?i)bearer\s+eyJ[a-zA-Z0-9_\-\.]+\.[a-zA-Z0-9_\-\.]+")
SSN_REGEX = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
AADHAAR_REGEX = re.compile(r"\b[2-9]\d{3}\s?\d{4}\s?\d{4}\b")
URL_REGEX = re.compile(r"https?://([^\s/$.?#].[^\s]*)", re.IGNORECASE)


@dataclass
class AuditLogger:
    """Audit logger tracking privacy sanitization actions and compliance events."""

    total_scanned: int = 0
    total_sanitized: int = 0
    sanitizations_by_type: dict[str, int] = field(
        default_factory=lambda: {
            "email": 0,
            "phone": 0,
            "card": 0,
            "credential": 0,
            "national_id": 0,
            "url": 0,
            "fallback_recovery": 0,
        }
    )
    audit_events: list[dict[str, Any]] = field(default_factory=list)

    def log_sanitization(
        self, record_id: str, pii_type: str, original_field: str, details: str
    ) -> None:
        self.total_sanitized += 1
        if pii_type in self.sanitizations_by_type:
            self.sanitizations_by_type[pii_type] += 1
        else:
            self.sanitizations_by_type[pii_type] = 1

        event = {
            "record_id": record_id,
            "pii_type": pii_type,
            "field": original_field,
            "details": details,
        }
        self.audit_events.append(event)
        logger.info(
            "Privacy sanitization applied [Record ID: %s] Field: %s Type: %s Details: %s",
            record_id,
            original_field,
            pii_type,
            details,
        )

    def log_recovery(self, record_id: str, reason: str) -> None:
        self.sanitizations_by_type["fallback_recovery"] = (
            self.sanitizations_by_type.get("fallback_recovery", 0) + 1
        )
        event = {
            "record_id": record_id,
            "pii_type": "fallback_recovery",
            "field": "record",
            "details": reason,
        }
        self.audit_events.append(event)
        logger.warning(
            "Privacy sanitization fallback recovery invoked [Record ID: %s] Reason: %s",
            record_id,
            reason,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "total_scanned": self.total_scanned,
            "total_sanitized": self.total_sanitized,
            "sanitizations_by_type": dict(self.sanitizations_by_type),
            "audit_events_count": len(self.audit_events),
        }


class PrivacySanitizer:
    """On-device privacy sanitization engine for synthetic notification records."""

    def __init__(self, audit_logger: AuditLogger | None = None) -> None:
        self.audit_logger = audit_logger or AuditLogger()

    def sanitize_record(self, record: dict[str, Any]) -> dict[str, Any]:
        """Sanitize a notification record in-place or return a sanitized clone.

        Applies regex redaction for credentials, credit cards, emails, phones,
        national IDs, and URLs across text fields and entities.
        """
        self.audit_logger.total_scanned += 1
        record_id = str(record.get("id", "unknown"))

        try:
            # 1. Sanitize Title
            if "title" in record and isinstance(record["title"], str):
                record["title"] = self._sanitize_text(
                    record["title"], record_id, "title"
                )

            # 2. Sanitize Body
            if "body" in record and isinstance(record["body"], str):
                record["body"] = self._sanitize_text(
                    record["body"], record_id, "body"
                )

            # 3. Sanitize Entities
            if "entities" in record and isinstance(record["entities"], dict):
                entities = record["entities"]
                for key, val in list(entities.items()):
                    if isinstance(val, str):
                        entities[key] = self._sanitize_text(
                            val, record_id, f"entities.{key}"
                        )

            # 4. Enforce Safe Email Entities
            if record.get("contains_email") and "entities" in record:
                domain = record["entities"].get("email_domain")
                if domain and domain.lower() not in SAFE_DOMAINS:
                    record["entities"]["email_domain"] = "example.com"
                    self.audit_logger.log_sanitization(
                        record_id,
                        "email",
                        "entities.email_domain",
                        f"Converted unsafe domain '{domain}' to example.com",
                    )

            return record

        except Exception as exc:
            self.audit_logger.log_recovery(record_id, f"Exception during sanitization: {exc}")
            return self._fallback_recovery(record)

    def _sanitize_text(self, text: str, record_id: str, field_name: str) -> str:
        sanitized = text

        # A. Credentials and Passwords
        def _redact_cred(match: re.Match) -> str:
            key, val = match.group(1), match.group(2)
            self.audit_logger.log_sanitization(
                record_id, "credential", field_name, f"Redacted cleartext {key}"
            )
            return f"{key}: [REDACTED_{key.upper()}]"

        sanitized = CREDENTIAL_REGEX.sub(_redact_cred, sanitized)

        if JWT_REGEX.search(sanitized):
            sanitized = JWT_REGEX.sub("Bearer [REDACTED_TOKEN]", sanitized)
            self.audit_logger.log_sanitization(
                record_id, "credential", field_name, "Redacted Bearer JWT token"
            )

        # B. Credit / Debit Cards
        if CARD_REGEX.search(sanitized):
            sanitized = CARD_REGEX.sub("[REDACTED_CARD]", sanitized)
            self.audit_logger.log_sanitization(
                record_id, "card", field_name, "Redacted credit/debit card PAN"
            )

        # C. Email Addresses
        def _sanitize_email(match: re.Match) -> str:
            user, domain = match.group(1), match.group(2)
            if domain.lower() not in SAFE_DOMAINS:
                self.audit_logger.log_sanitization(
                    record_id, "email", field_name, f"Converted email domain {domain} to example.com"
                )
                return f"{user}@example.com"
            return match.group(0)

        sanitized = EMAIL_REGEX.sub(_sanitize_email, sanitized)

        # D. Phone Numbers (when explicit phone pattern matched and field is not purely a numeric amount)
        # Avoid matching short numbers like timestamps, amounts, or IDs
        def _sanitize_phone(match: re.Match) -> str:
            matched_str = match.group(0)
            # Only match if it's 10+ digits or formatted phone number
            digits_only = re.sub(r"\D", "", matched_str)
            if len(digits_only) >= 10:
                self.audit_logger.log_sanitization(
                    record_id, "phone", field_name, "Redacted phone number"
                )
                return "[REDACTED_PHONE]"
            return matched_str

        # Only check phone regex if text contains phone indicators or candidate pattern
        if PHONE_REGEX.search(sanitized):
            sanitized = PHONE_REGEX.sub(_sanitize_phone, sanitized)

        # E. SSN & Aadhaar
        if SSN_REGEX.search(sanitized):
            sanitized = SSN_REGEX.sub("[REDACTED_NATIONAL_ID]", sanitized)
            self.audit_logger.log_sanitization(
                record_id, "national_id", field_name, "Redacted SSN"
            )

        if AADHAAR_REGEX.search(sanitized):
            sanitized = AADHAAR_REGEX.sub("[REDACTED_NATIONAL_ID]", sanitized)
            self.audit_logger.log_sanitization(
                record_id, "national_id", field_name, "Redacted Aadhaar number"
            )

        # F. External URLs
        def _sanitize_url(match: re.Match) -> str:
            full_url = match.group(0)
            domain = match.group(1)
            # Check domain part
            main_domain = domain.split("/")[0].split(":")[0].lower()
            if main_domain not in SAFE_DOMAINS and main_domain != "example.com":
                self.audit_logger.log_sanitization(
                    record_id, "url", field_name, f"Sanitized external URL domain {main_domain}"
                )
                return "https://example.com"
            return full_url

        if URL_REGEX.search(sanitized):
            sanitized = URL_REGEX.sub(_sanitize_url, sanitized)

        return sanitized

    def _fallback_recovery(self, record: dict[str, Any]) -> dict[str, Any]:
        """Fallback error recovery path for records encountering errors during sanitization."""
        fallback = dict(record)
        for text_field in ("title", "body"):
            if isinstance(fallback.get(text_field), str):
                # Basic brute-force scrub
                val = fallback[text_field]
                val = EMAIL_REGEX.sub(r"\1@example.com", val)
                val = CARD_REGEX.sub("[REDACTED_CARD]", val)
                val = CREDENTIAL_REGEX.sub(r"\1: [REDACTED]", val)
                fallback[text_field] = val
        return fallback


def validate_privacy_compliance(record: dict[str, Any]) -> list[str]:
    """Validate that a record satisfies privacy sanitization guardrails."""
    errors: list[str] = []
    title = str(record.get("title", ""))
    body = str(record.get("body", ""))
    full_text = f"{title} {body}"

    # 1. Unredacted Credentials Check
    if CREDENTIAL_REGEX.search(full_text):
        errors.append("contains unredacted cleartext credentials or passwords")

    if JWT_REGEX.search(full_text):
        errors.append("contains unredacted Bearer JWT token")

    # 2. Unredacted Credit Card Check
    if CARD_REGEX.search(full_text):
        errors.append("contains unredacted credit/debit card PAN")

    # 3. Unapproved Email Domain Check
    for match in EMAIL_REGEX.finditer(full_text):
        domain = match.group(2).lower()
        if domain not in SAFE_DOMAINS:
            errors.append(f"contains unapproved email domain '@{domain}'")

    # 4. Unredacted National ID Check
    if SSN_REGEX.search(full_text) or AADHAAR_REGEX.search(full_text):
        errors.append("contains unredacted SSN or Aadhaar national ID")

    # 5. External URL Check
    for match in URL_REGEX.finditer(full_text):
        domain = match.group(1).split("/")[0].split(":")[0].lower()
        if domain not in SAFE_DOMAINS and domain != "example.com":
            errors.append(f"contains external non-test URL domain '{domain}'")

    return errors
