from __future__ import annotations

import math
import random
import re
from typing import Any

# Optional Presidio integration
try:
    from presidio_analyzer import AnalyzerEngine
    from presidio_anonymizer import AnonymizerEngine

    _HAS_PRESIDIO = True
    _ANALYZER = AnalyzerEngine()
    _ANONYMIZER = AnonymizerEngine()
except ImportError:
    _HAS_PRESIDIO = False
    _ANALYZER = None
    _ANONYMIZER = None


_NAME_HONORIFIC_RE = re.compile(
    r"\b(?:Dr\.|Mr\.|Mrs\.|Ms\.|Prof\.)\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\b"
)

_KNOWN_NAMES = {
    "Riya", "Arjun", "Nisha", "Karan", "Meera", "Priya", "Rahul", "Aarav",
    "Ananya", "Priyan", "Vihaan", "Sharma", "Verma", "Patel", "Gupta", "Singh",
    "Kumar", "Joshi", "Reddy", "Rao", "Nair", "Iyer", "Deshmukh", "Chowdhury",
    "Banerjee", "Chatterjee", "Bhat", "Mehta", "Shah", "Siddharth", "Neha",
    "Amit", "Kavya", "Sneha", "Rohan", "Tanvi", "Aditya", "Pooja", "Vikram", "Shreya", "Deepak"
}

_KNOWN_NAMES_RE = re.compile(
    r"\b(?:" + "|".join(re.escape(name) for name in sorted(_KNOWN_NAMES, key=len, reverse=True)) + r")\b"
)

_NAME_CONTEXT_RE = re.compile(
    r"\b(?:received from|paid you|request from|delivery with|is on the way|with|commented on|reacted|sent an email|requested your review|mentioned you|assigned|shared|is arriving)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\b"
)

_TITLE_BODY_PREFIX_NAME_RE = re.compile(
    r"^([A-Z][a-z]+)(?=:|$)"
)

_CREDIT_CARD_RE = re.compile(
    r"\b(?:\d[ -]*?){13,19}\b"
)
_CARD_ENDING_RE = re.compile(
    r"\bcard ending (\d+)\b", re.IGNORECASE
)
_ACCOUNT_ENDING_RE = re.compile(
    r"\b(A/c|account|Account|Loan account|mobile) ending (\d+)\b", re.IGNORECASE
)
_AC_NUM_RE = re.compile(
    r"\bA/c (\d+)\b", re.IGNORECASE
)


def redact_pii_text(text: str) -> str:
    """Scrub personal names, credit card numbers, and financial account numbers."""
    if not text:
        return text

    # 1. Optional Presidio Analysis
    if _HAS_PRESIDIO and _ANALYZER and _ANONYMIZER:
        try:
            results = _ANALYZER.analyze(text=text, entities=["PERSON", "CREDIT_CARD"], language="en")
            if results:
                text = _ANONYMIZER.anonymize(text=text, analyzer_results=results).text
        except Exception:
            pass

    # 2. Credit Card & Financial Account Identifiers
    text = _CREDIT_CARD_RE.sub("[CREDIT_CARD]", text)
    text = _CARD_ENDING_RE.sub("card ending [CREDIT_CARD]", text)
    text = _ACCOUNT_ENDING_RE.sub(r"\1 ending [ACCOUNT_NUMBER]", text)
    text = _AC_NUM_RE.sub("A/c [ACCOUNT_NUMBER]", text)

    # 3. Personal Names Honorific & Context Rules
    text = _NAME_HONORIFIC_RE.sub("Dr. [NAME]", text)

    def _replace_context(match: re.Match) -> str:
        full_match = match.group(0)
        name_part = match.group(1)
        if name_part and name_part not in {"Dr.", "Mr.", "Mrs.", "Ms."}:
            return full_match.replace(name_part, "[NAME]")
        return full_match

    text = _NAME_CONTEXT_RE.sub(_replace_context, text)
    text = _TITLE_BODY_PREFIX_NAME_RE.sub("[NAME]", text)

    # 4. Known Synthetic Names Dictionary Match
    text = _KNOWN_NAMES_RE.sub("[NAME]", text)

    return text


def laplace_noise(scale: float = 1.0) -> float:
    """Sample from Laplace distribution Lap(0, scale) using inverse transform sampling."""
    u = random.uniform(-0.5, 0.5)
    if u == 0:
        u = 1e-12
    return -scale * math.copysign(1.0, u) * math.log(1.0 - 2.0 * abs(u))


def perturb_score(score: float | int, epsilon: float = 1.0, sensitivity: float = 1.0) -> float:
    """Inject Laplace noise into a score to satisfy differential privacy (epsilon=1.0)."""
    if epsilon <= 0:
        return float(score)
    scale = sensitivity / epsilon
    noise = laplace_noise(scale)
    perturbed = float(score) + noise
    clamped = max(0.0, min(100.0, perturbed))
    return round(clamped, 2)


def process_record_privacy(
    record: dict[str, Any],
    redact_pii: bool = True,
    perturb_scores: bool = True,
    epsilon: float = 1.0,
) -> dict[str, Any]:
    """Pass a generated notification record through PII redaction and score perturbation."""
    record_copy = dict(record)

    if redact_pii:
        title = record_copy.get("title", "")
        body = record_copy.get("body", "")
        if title:
            title_redacted = redact_pii_text(title)
            if len(title_redacted) > 50:
                title_redacted = title_redacted[:49].rstrip(" .,;:-") + "…"
            record_copy["title"] = title_redacted
        if body:
            body_redacted = redact_pii_text(body)
            if len(body_redacted) > 140:
                body_redacted = body_redacted[:139].rstrip(" .,;:-") + "…"
            record_copy["body"] = body_redacted
        if "priority_reason" in record_copy:
            record_copy["priority_reason"] = redact_pii_text(str(record_copy["priority_reason"]))

    if perturb_scores:
        if "review_score" in record_copy:
            record_copy["review_score"] = perturb_score(record_copy["review_score"], epsilon=epsilon)
        if "priority_score" in record_copy:
            record_copy["priority_score"] = perturb_score(record_copy["priority_score"], epsilon=epsilon)
        if "look_again_score" in record_copy:
            record_copy["look_again_score"] = perturb_score(record_copy["look_again_score"], epsilon=epsilon)

    return record_copy
