import os
import unittest
from unittest.mock import patch

from generator.base import NotificationDatasetGenerator, validate_ollama_url


class TestUrlValidation(unittest.TestCase):
    def test_loopback_http_urls_permitted(self):
        loopback_urls = [
            "http://localhost:11434",
            "http://127.0.0.1:11434",
            "http://[::1]:11434",
            "localhost:11434",
            "127.0.0.1:11434",
        ]
        for url in loopback_urls:
            validated = validate_ollama_url(url)
            self.assertTrue(validated.startswith("http://"))

    def test_external_https_urls_permitted(self):
        external_https = [
            "https://example.com/api",
            "https://ollama.internal:8443/generate",
        ]
        for url in external_https:
            validated = validate_ollama_url(url)
            self.assertEqual(validated, url)

    def test_external_cleartext_http_prohibited(self):
        insecure_urls = [
            "http://example.com/api",
            "http://192.168.1.100:11434",
            "http://ollama.internal:11434",
        ]
        for url in insecure_urls:
            with self.assertRaises(ValueError) as ctx:
                validate_ollama_url(url)
            self.assertIn("Cleartext HTTP traffic is prohibited", str(ctx.exception))

    def test_invalid_scheme_prohibited(self):
        invalid_urls = [
            "ftp://localhost:11434",
            "gopher://localhost:11434",
        ]
        for url in invalid_urls:
            with self.assertRaises(ValueError) as ctx:
                validate_ollama_url(url)
            self.assertIn("Invalid URL scheme", str(ctx.exception))

    def test_empty_url_prohibited(self):
        with self.assertRaises(ValueError):
            validate_ollama_url("")

    def test_generator_validates_ollama_url(self):
        # Valid loopback URL succeeds
        gen = NotificationDatasetGenerator(ollama_url="http://localhost:11434")
        self.assertEqual(gen.ollama_url, "http://localhost:11434")

        # Insecure remote HTTP URL raises ValueError
        with self.assertRaises(ValueError):
            NotificationDatasetGenerator(ollama_url="http://example.com/api")

    def test_generator_resolves_ollama_host_env(self):
        with patch.dict(os.environ, {"OLLAMA_HOST": "http://example.com/api"}):
            with self.assertRaises(ValueError):
                NotificationDatasetGenerator()

        with patch.dict(os.environ, {"OLLAMA_HOST": "http://localhost:11434"}):
            gen = NotificationDatasetGenerator()
            self.assertEqual(gen.ollama_url, "http://localhost:11434")


if __name__ == "__main__":
    unittest.main()
