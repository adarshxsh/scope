from __future__ import annotations

import hashlib


def text_fingerprint(title: str, body: str) -> str:
    normalized = " ".join(f"{title} {body}".lower().split())
    return hashlib.sha1(normalized.encode("utf-8")).hexdigest()
