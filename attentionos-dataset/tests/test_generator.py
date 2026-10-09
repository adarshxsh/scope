from __future__ import annotations

import os
import pytest
from generator.base import NotificationDatasetGenerator


def test_default_endpoint_uses_https():
    generator = NotificationDatasetGenerator()
    assert generator.ollama_endpoint == "https://localhost:11434/api/generate"


def test_http_endpoint_without_allow_http_raises_error():
    with pytest.raises(ValueError, match="Unencrypted HTTP model endpoint"):
        NotificationDatasetGenerator(
            ollama_endpoint="http://localhost:11434/api/generate",
            allow_http=False,
        )


def test_http_endpoint_with_allow_http_succeeds():
    generator = NotificationDatasetGenerator(
        ollama_endpoint="http://localhost:11434/api/generate",
        allow_http=True,
    )
    assert generator.ollama_endpoint == "http://localhost:11434/api/generate"


def test_https_endpoint_succeeds():
    generator = NotificationDatasetGenerator(
        ollama_endpoint="https://secure-model-server.local:11434/api/generate"
    )
    assert generator.ollama_endpoint == "https://secure-model-server.local:11434/api/generate"


def test_env_var_ollama_base_url_https(monkeypatch):
    monkeypatch.setenv("OLLAMA_BASE_URL", "https://ollama.internal:11434")
    generator = NotificationDatasetGenerator()
    assert generator.ollama_endpoint == "https://ollama.internal:11434/api/generate"


def test_env_var_ollama_base_url_http_raises_error(monkeypatch):
    monkeypatch.setenv("OLLAMA_BASE_URL", "http://ollama.internal:11434")
    with pytest.raises(ValueError, match="Unencrypted HTTP model endpoint"):
        NotificationDatasetGenerator()


def test_invalid_scheme_raises_error():
    with pytest.raises(ValueError, match="Unsupported scheme"):
        NotificationDatasetGenerator(ollama_endpoint="ftp://localhost:11434")
