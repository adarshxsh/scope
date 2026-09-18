from __future__ import annotations

import copy
import random
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable


# Regular Expressions for PII Detection
_EMAIL_REGEX = re.compile(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'
)

_PHONE_REGEX = re.compile(
    r'\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{4}\b|\b1800[-.\s]?[A-Z0-9]{3,4}[-.\s]?[A-Z0-9]{4}\b',
    re.IGNORECASE,
)

_ORDER_ID_REGEX = re.compile(
    r'\b(?:order|ord|package|tracking|awb)\s*#?\s*([A-Z0-9-]{4,})\b|\b#?(OD\d{4,})\b',
    re.IGNORECASE,
)

_REF_ID_REGEX = re.compile(
    r'\b(?:ref|reference|pnr|txn|txnid|transaction|utr|upi\s+ref)\s*[:#-]?\s*([A-Z0-9-]{4,})\b',
    re.IGNORECASE,
)

_ACCOUNT_LAST4_REGEX = re.compile(
    r'\b(?:ending|card|account|a/c|mobile)\s+(?:ending\s+)?(\d{4})\b',
    re.IGNORECASE,
)

_OTP_CONTEXT_REGEX = re.compile(
    r'\b(?:code|otp|pin|passcode|verification|verify|2fa|auth|authentication|sign-in|login)\b',
    re.IGNORECASE,
)

_OTP_DIGITS_REGEX = re.compile(
    r'\b\d{4,8}\b'
)

_MONEY_REGEX = re.compile(
    r'(₹|rs\.?|inr|usd|\$|eur|€|gbp|£|aed)\s*([0-9]+(?:,[0-9]{2,3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)',
    re.IGNORECASE,
)

# Known first names and name pattern regexes
_KNOWN_FIRST_NAMES = {
    "fariq", "harsh", "gunbir", "lakshit", "adya", "riya", "arjun", "nisha",
    "karan", "meera", "alice", "bob", "charlie", "david", "eve", "frank",
    "rahul", "priya", "amit", "sneh", "rohit", "ananya", "vikram", "pooja",
    "neha", "siddharth", "aarti", "deepak", "tanvi", "aakash", "shreya"
}

_DOCTOR_NAME_REGEX = re.compile(
    r'\bDr\.\s+([A-Z][a-z]+)\b'
)

_NAME_CONTEXT_PATTERNS = [
    re.compile(r'\bfrom\s+([A-Z][a-z]+)\b'),
    re.compile(r'\bwith\s+([A-Z][a-z]+)\b'),
    re.compile(r'\b([A-Z][a-z]+)\s+(?:paid|requested|assigned|shared|commented|reacted|sent|is arriving|is on the way|is preparing)\b'),
    re.compile(r'^([A-Z][a-z]+)$'),
    re.compile(r'^([A-Z][a-z]+):'),
]


class PrivacySanitizer:
    """Export middleware layer that redacts PII and perturbs continuous features."""

    def __init__(
        self,
        enabled: bool = True,
        perturbation_bound: float = 0.1,
        seed: int | None = None,
    ) -> None:
        self.enabled = enabled
        self.perturbation_bound = max(0.0, float(perturbation_bound))
        self.random = random.Random(seed)

    def sanitize(self, record: dict[str, Any]) -> dict[str, Any]:
        """Sanitizes a single notification record prior to export serialization."""
        if not self.enabled:
            return record

        sanitized = copy.deepcopy(record)

        title = str(sanitized.get("title", ""))
        body = str(sanitized.get("body", ""))
        combined = f"{title}\n{body}"

        # Determine if OTP context is present
        is_otp = (
            bool(sanitized.get("contains_otp")) or
            str(sanitized.get("category", "")).upper() == "OTP" or
            bool(_OTP_CONTEXT_REGEX.search(combined))
        )

        # Gather names to redact
        names_to_redact: set[str] = set()
        self._collect_names(title, body, names_to_redact)

        # Redact text fields
        title_clean = self._redact_text(title, names_to_redact, is_otp_context=is_otp)
        body_clean = self._redact_text(body, names_to_redact, is_otp_context=is_otp)

        # Apply monetary perturbation
        title_clean, body_clean, sanitized_entities = self._perturb_amounts(
            title_clean, body_clean, sanitized.get("entities")
        )

        sanitized["title"] = title_clean
        sanitized["body"] = body_clean

        # Redact and perturb entities metadata
        if sanitized_entities is not None:
            sanitized["entities"] = self._sanitize_entities(sanitized_entities)

        # Perturb timestamps in android metadata and deadline
        if "android" in sanitized and isinstance(sanitized["android"], dict):
            android = copy.deepcopy(sanitized["android"])
            if "timestamp" in android and android["timestamp"]:
                android["timestamp"] = self._perturb_timestamp(str(android["timestamp"]))
            sanitized["android"] = android

        if sanitized.get("deadline"):
            sanitized["deadline"] = self._perturb_timestamp(str(sanitized["deadline"]))

        # If record contains pre-populated features list, re-extract features
        if "features" in sanitized and isinstance(sanitized["features"], list):
            try:
                from utils.feature_extractor import extract_features
                sanitized["features"] = extract_features(sanitized)
            except ImportError:
                try:
                    from training.utils.feature_extractor import extract_features
                    sanitized["features"] = extract_features(sanitized)
                except ImportError:
                    pass

        return sanitized

    def sanitize_stream(self, records: Iterable[dict[str, Any]]) -> Iterable[dict[str, Any]]:
        """Applies sanitization across an iterable stream of records."""
        for record in records:
            yield self.sanitize(record)

    def _collect_names(self, title: str, body: str, names: set[str]) -> None:
        combined = f"{title}\n{body}"

        for match in _DOCTOR_NAME_REGEX.finditer(combined):
            names.add(match.group(1))

        for pattern in _NAME_CONTEXT_PATTERNS:
            for match in pattern.finditer(title):
                names.add(match.group(1))
            for match in pattern.finditer(body):
                names.add(match.group(1))

        for token in re.split(r'\W+', combined):
            if token.lower() in _KNOWN_FIRST_NAMES:
                names.add(token)

    def _redact_text(self, text: str, names: set[str], is_otp_context: bool = False) -> str:
        if not text:
            return text

        result = text

        # 1. Redact Doctor names
        result = _DOCTOR_NAME_REGEX.sub(r'Dr. <NAME>', result)

        # 2. Redact emails FIRST before word/name matching
        result = _EMAIL_REGEX.sub("<EMAIL>", result)

        # 3. Redact phone numbers
        result = _PHONE_REGEX.sub("<PHONE>", result)

        # 4. Redact Order IDs
        def _order_replacer(match: re.Match) -> str:
            full = match.group(0)
            prefix = full[:match.start(1) - match.start(0)] if match.lastindex else ""
            if prefix:
                return f"{prefix}<ORDER_ID>"
            return "<ORDER_ID>"

        result = _ORDER_ID_REGEX.sub(_order_replacer, result)

        # 5. Redact Reference IDs / PNRs / Transaction IDs
        def _ref_replacer(match: re.Match) -> str:
            full = match.group(0)
            prefix = full[:match.start(1) - match.start(0)] if match.lastindex else ""
            if prefix:
                return f"{prefix}<REF_ID>"
            return "<REF_ID>"

        result = _REF_ID_REGEX.sub(_ref_replacer, result)

        # 6. Redact Account / Card ending numbers
        result = _ACCOUNT_LAST4_REGEX.sub(r'\g<0>'[:-4] + "<REF_ID>", result)

        # 7. Redact OTP digits in OTP context
        if is_otp_context or _OTP_CONTEXT_REGEX.search(result):
            def _otp_replacer(match: re.Match) -> str:
                val = match.group(0)
                if val.isdigit() and 2020 <= int(val) <= 2030:
                    return val
                return "<OTP>"

            result = _OTP_DIGITS_REGEX.sub(_otp_replacer, result)

        # 8. Redact specific collected personal names
        for name in sorted(names, key=len, reverse=True):
            if not name or name in {"Dr", "Mr", "Mrs", "Ms"}:
                continue
            pattern = re.compile(rf'\b{re.escape(name)}\b', re.IGNORECASE)
            result = pattern.sub("<NAME>", result)

        return result

    def _perturb_amounts(
        self, title: str, body: str, entities: dict[str, Any] | None
    ) -> tuple[str, str, dict[str, Any] | None]:
        title_out = title
        body_out = body
        entities_out = copy.deepcopy(entities) if entities is not None else None

        if self.perturbation_bound == 0.0:
            return title_out, body_out, entities_out

        amount = None
        if entities_out and "amount" in entities_out and isinstance(entities_out["amount"], (int, float)):
            amount = float(entities_out["amount"])

        def _replace_money_match(match: re.Match) -> str:
            symbol = match.group(1)
            raw_val = match.group(2).replace(',', '')
            try:
                val = float(raw_val)
            except ValueError:
                return match.group(0)

            noise = self.random.uniform(-self.perturbation_bound, self.perturbation_bound)
            perturbed_val = max(1.0, round(val * (1.0 + noise)))
            if "." in raw_val:
                formatted = f"{perturbed_val:.2f}"
            else:
                formatted = f"{int(perturbed_val)}"
            return f"{symbol}{formatted}"

        title_out = _MONEY_REGEX.sub(_replace_money_match, title_out)
        body_out = _MONEY_REGEX.sub(_replace_money_match, body_out)

        if amount is not None and amount > 0:
            noise = self.random.uniform(-self.perturbation_bound, self.perturbation_bound)
            perturbed_amount = max(1.0, round(amount * (1.0 + noise)))
            entities_out["amount"] = int(perturbed_amount) if isinstance(entities.get("amount"), int) else perturbed_amount

        return title_out, body_out, entities_out

    def _sanitize_entities(self, entities: dict[str, Any]) -> dict[str, Any]:
        result = copy.deepcopy(entities)
        for key, value in result.items():
            if not isinstance(value, str):
                continue
            val = _EMAIL_REGEX.sub("<EMAIL>", value)
            val = _PHONE_REGEX.sub("<PHONE>", val)

            if key in {"reference_id", "ref", "pnr", "order_id"}:
                val = "<REF_ID>" if key != "order_id" else "<ORDER_ID>"

            result[key] = val
        return result

    def _perturb_timestamp(self, ts_str: str) -> str:
        if not ts_str:
            return ts_str
        try:
            ts_clean = ts_str
            if len(ts_clean) > 19 and ts_clean[-3] == ':':
                ts_clean = ts_clean[:-3] + ts_clean[-2:]
            dt = datetime.fromisoformat(ts_clean)
        except Exception:
            return ts_str

        max_minutes = int(self.perturbation_bound * 60) if self.perturbation_bound > 0 else 15
        max_minutes = max(1, max_minutes)
        offset_minutes = self.random.randint(-max_minutes, max_minutes)
        dt_perturbed = dt + timedelta(minutes=offset_minutes)

        return dt_perturbed.isoformat()
