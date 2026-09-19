from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger("attentionos.dataset.prompt_guard")

# Regular expressions for identifying system role markers, control tags, and prompt injection patterns
ROLE_TOKENS_PATTERN = re.compile(
    r"(<\|im_start\|>|<\|im_end\|>|\[INST\]|\[/INST\]|<sys>|</sys>|<system>|</system>|<<SYS>>|<</SYS>>)",
    re.IGNORECASE,
)

SYSTEM_PREFIX_PATTERN = re.compile(
    r"^\s*(system|user|human|assistant|ai)\s*:\s*",
    re.IGNORECASE | re.MULTILINE,
)

PROMPT_INJECTION_KEYWORDS_PATTERN = re.compile(
    r"(ignore\s+(previous|above|all)\s+instructions|disregard\s+(above|previous)|override\s+rules|system\s+prompt|instead\s+return|you\s+are\s+now|forget\s+all)",
    re.IGNORECASE,
)

MARKDOWN_FENCE_PATTERN = re.compile(r"```[a-z]*")
JINJA_TAG_PATTERN = re.compile(r"(\{\{|\}\}|\{%|%\}|\{#|#\})")


@dataclass
class TelemetryTracker:
    ollama_attempts: int = 0
    ollama_successes: int = 0
    sanitized_inputs: int = 0
    rejected_outputs: int = 0
    fallback_events: int = 0
    validation_errors: dict[str, int] = field(default_factory=dict)

    def record_validation_error(self, error_type: str) -> None:
        self.validation_errors[error_type] = self.validation_errors.get(error_type, 0) + 1

    def to_dict(self) -> dict[str, Any]:
        return {
            "ollama_attempts": self.ollama_attempts,
            "ollama_successes": self.ollama_successes,
            "sanitized_inputs": self.sanitized_inputs,
            "rejected_outputs": self.rejected_outputs,
            "fallback_events": self.fallback_events,
            "validation_errors": dict(self.validation_errors),
        }


def sanitize_prompt_input(text: str) -> tuple[str, bool]:
    """
    Sanitizes raw text input to prevent LLM prompt injection and structural breakout.
    Returns (sanitized_text, is_modified).
    """
    if not isinstance(text, str):
        return str(text), False

    original = text
    cleaned = text

    # Remove role tokens / prompt injection boundary sequences
    cleaned = ROLE_TOKENS_PATTERN.sub("", cleaned)
    cleaned = SYSTEM_PREFIX_PATTERN.sub("", cleaned)
    cleaned = PROMPT_INJECTION_KEYWORDS_PATTERN.sub("", cleaned)

    # Strip markdown code fences
    cleaned = MARKDOWN_FENCE_PATTERN.sub("", cleaned)

    # Escape Jinja delimiters
    cleaned = JINJA_TAG_PATTERN.sub("", cleaned)

    # Replace newlines and carriage returns with spaces for inline string fields
    cleaned = cleaned.replace("\r", " ").replace("\n", " ")

    # Collapse multiple spaces
    cleaned = " ".join(cleaned.split())

    is_modified = cleaned != original
    if is_modified:
        logger.debug("Sanitized prompt input (injection or control characters removed).")

    return cleaned, is_modified


def escape_context(ctx: dict[str, Any]) -> tuple[dict[str, Any], int]:
    """
    Recursively sanitizes context dictionary values to prevent prompt injection.
    Returns (sanitized_ctx, sanitized_count).
    """
    sanitized_ctx: dict[str, Any] = {}
    sanitized_count = 0

    for key, val in ctx.items():
        if isinstance(val, str):
            clean_val, modified = sanitize_prompt_input(val)
            sanitized_ctx[key] = clean_val
            if modified:
                sanitized_count += 1
        elif isinstance(val, dict):
            sub_ctx, sub_count = escape_context(val)
            sanitized_ctx[key] = sub_ctx
            sanitized_count += sub_count
        elif isinstance(val, list):
            clean_list = []
            for item in val:
                if isinstance(item, str):
                    clean_item, modified = sanitize_prompt_input(item)
                    clean_list.append(clean_item)
                    if modified:
                        sanitized_count += 1
                elif isinstance(item, dict):
                    sub_ctx, sub_count = escape_context(item)
                    clean_list.append(sub_ctx)
                    sanitized_count += sub_count
                else:
                    clean_list.append(item)
            sanitized_ctx[key] = clean_list
        else:
            sanitized_ctx[key] = val

    return sanitized_ctx, sanitized_count


def load_system_template() -> str:
    """Loads system prompt template from disk or returns inline default."""
    template_path = Path(__file__).parent.parent / "templates" / "ollama_prompt.txt"
    if template_path.is_file():
        try:
            return template_path.read_text(encoding="utf-8")
        except OSError:
            pass
    return (
        "You are Gemma 3 9B running locally through Ollama.\n"
        "Your task is to generate synthetic Android notifications for AttentionOS Dataset.\n"
        "Return ONLY valid JSON with keys 'title' and 'body'.\n"
        "Title: max 50 chars. Body: max 140 chars."
    )


def build_structured_prompt(
    scenario_type: str,
    intent: str,
    ctx: dict[str, Any],
    entities: dict[str, Any] | None = None,
) -> str:
    """
    Constructs a structurally safe Ollama prompt. Inputs are embedded inside a JSON block
    to enforce structural separation between system instructions and untrusted input data.
    """
    system_prompt = load_system_template()

    # Build input payload as a clean JSON block
    input_payload = {
        "app_context": ctx.get("app_context", ""),
        "notification_type": scenario_type,
        "intent": intent,
        "entities": entities or {},
    }

    input_json_str = json.dumps(input_payload, ensure_ascii=False, indent=2)

    prompt = (
        f"{system_prompt}\n\n"
        "--- INPUT DATA (JSON) ---\n"
        "Generate a notification adhering strictly to the parameters in this JSON payload:\n"
        f"```json\n{input_json_str}\n```\n\n"
        "--- REQUIRED OUTPUT FORMAT ---\n"
        "Return ONLY a JSON object with 'title' and 'body' fields:\n"
        '{\n  "title": "...",\n  "body": "..."\n}'
    )
    return prompt


def validate_ollama_output(raw_response: str) -> tuple[dict[str, str] | None, str | None]:
    """
    Parses and validates LLM response against schema constraints and security guardrails.
    Returns (parsed_dict, error_message).
    """
    if not raw_response or not isinstance(raw_response, str):
        return None, "empty_response"

    # Attempt JSON extraction
    raw_cleaned = raw_response.strip()
    parsed: dict[str, Any] | None = None

    try:
        parsed = json.loads(raw_cleaned)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", raw_cleaned, flags=re.DOTALL)
        if match:
            try:
                parsed = json.loads(match.group(0))
            except json.JSONDecodeError:
                pass

    if not isinstance(parsed, dict):
        return None, "invalid_json_structure"

    title = parsed.get("title")
    body = parsed.get("body")

    if not isinstance(title, str) or not isinstance(body, str):
        return None, "missing_title_or_body"

    title = title.strip()
    body = body.strip()

    if not title or not body:
        return None, "empty_title_or_body"

    # Check length limits
    if len(title) > 50:
        title = title[:49] + "…"
    if len(body) > 140:
        body = body[:139] + "…"

    # Guardrail: Check for prompt leakage or echo of instruction phrases
    combined_text = f"{title} {body}".lower()
    if PROMPT_INJECTION_KEYWORDS_PATTERN.search(combined_text) or ROLE_TOKENS_PATTERN.search(combined_text):
        return None, "prompt_leakage_detected"

    if "```" in combined_text or "--- input data" in combined_text:
        return None, "structural_code_leakage"

    return {"title": title, "body": body}, None
