from __future__ import annotations

import os
from unittest.mock import patch
import pytest

from generator.base import NotificationDatasetGenerator


def test_default_ollama_endpoint():
    with patch.dict(os.environ, {}, clear=True):
        gen = NotificationDatasetGenerator()
        assert gen._get_ollama_endpoint() == "http://localhost:11434/api/generate"


def test_ollama_base_url_env_var():
    with patch.dict(os.environ, {"OLLAMA_BASE_URL": "http://ollama-server:11434"}, clear=True):
        gen = NotificationDatasetGenerator()
        assert gen._get_ollama_endpoint() == "http://ollama-server:11434/api/generate"


def test_ollama_host_env_var():
    with patch.dict(os.environ, {"OLLAMA_HOST": "10.0.0.50:11434"}, clear=True):
        gen = NotificationDatasetGenerator()
        assert gen._get_ollama_endpoint() == "http://10.0.0.50:11434/api/generate"


def test_ollama_base_url_param_override():
    with patch.dict(os.environ, {"OLLAMA_BASE_URL": "http://ignored-env:11434"}, clear=True):
        gen = NotificationDatasetGenerator(ollama_base_url="https://custom-domain.com:8443")
        assert gen._get_ollama_endpoint() == "https://custom-domain.com:8443/api/generate"


def test_ollama_endpoint_with_api_path():
    gen = NotificationDatasetGenerator(ollama_base_url="http://localhost:11434/api")
    assert gen._get_ollama_endpoint() == "http://localhost:11434/api/generate"


def test_ollama_endpoint_with_full_path():
    gen = NotificationDatasetGenerator(ollama_base_url="http://localhost:11434/api/generate")
    assert gen._get_ollama_endpoint() == "http://localhost:11434/api/generate"
