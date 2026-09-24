import io
import json
import os
import unittest
from unittest.mock import MagicMock, patch

from generator.base import (
    NotificationDatasetGenerator,
    _is_loopback,
    validate_ollama_endpoint,
)


class TestOllamaEndpointValidation(unittest.TestCase):
    def test_is_loopback(self) -> None:
        self.assertTrue(_is_loopback("localhost"))
        self.assertTrue(_is_loopback("LOCALHOST"))
        self.assertTrue(_is_loopback("127.0.0.1"))
        self.assertTrue(_is_loopback("127.0.0.2"))
        self.assertTrue(_is_loopback("::1"))
        self.assertFalse(_is_loopback("192.168.1.1"))
        self.assertFalse(_is_loopback("example.com"))
        self.assertFalse(_is_loopback(""))

    def test_valid_loopback_endpoints(self) -> None:
        self.assertEqual(
            validate_ollama_endpoint("http://localhost:11434"),
            "http://localhost:11434",
        )
        self.assertEqual(
            validate_ollama_endpoint("http://127.0.0.1:11434/api/generate"),
            "http://127.0.0.1:11434/api/generate",
        )
        self.assertEqual(
            validate_ollama_endpoint("http://[::1]:11434"),
            "http://[::1]:11434",
        )

    def test_valid_https_endpoints(self) -> None:
        self.assertEqual(
            validate_ollama_endpoint("https://ollama.internal.domain:11434"),
            "https://ollama.internal.domain:11434",
        )
        self.assertEqual(
            validate_ollama_endpoint("https://example.com/api/generate"),
            "https://example.com/api/generate",
        )

    def test_invalid_non_loopback_http_endpoints(self) -> None:
        invalid_urls = [
            "http://192.168.1.100:11434",
            "http://example.com:11434",
            "http://ollama.remote.io:11434",
            "http://10.0.0.1:11434",
        ]
        for url in invalid_urls:
            with self.subTest(url=url):
                with self.assertRaises(ValueError) as ctx:
                    validate_ollama_endpoint(url)
                self.assertIn("Cleartext HTTP", str(ctx.exception))

    def test_invalid_schemes(self) -> None:
        with self.assertRaises(ValueError):
            validate_ollama_endpoint("ftp://localhost:11434")

    @patch.dict(os.environ, {"OLLAMA_BASE_URL": "http://127.0.0.1:11434"})
    def test_env_var_override_valid(self) -> None:
        generator = NotificationDatasetGenerator(use_ollama=True)
        self.assertEqual(generator.ollama_base_url, "http://127.0.0.1:11434")

    @patch.dict(os.environ, {"OLLAMA_BASE_URL": "http://unauthorized-remote-host.com:11434"})
    def test_env_var_override_invalid_fails_fast(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            NotificationDatasetGenerator(use_ollama=True)
        self.assertIn("Cleartext HTTP", str(ctx.exception))

    @patch("urllib.request.urlopen")
    def test_dataset_generation_with_mocked_ollama(self, mock_urlopen: MagicMock) -> None:
        mock_response = MagicMock()
        mock_response.read.return_value = json.dumps(
            {"response": json.dumps({"title": "Test Title", "body": "Test Body"})}
        ).encode("utf-8")
        mock_response.__enter__.return_value = mock_response
        mock_urlopen.return_value = mock_response

        generator = NotificationDatasetGenerator(seed=42, use_ollama=True)
        records = list(generator.generate(5))
        self.assertEqual(len(records), 5)


if __name__ == "__main__":
    unittest.main()
