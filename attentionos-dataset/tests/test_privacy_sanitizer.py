from __future__ import annotations

import unittest
from sanitizer.privacy import AuditLogger, PrivacySanitizer, validate_privacy_compliance


class TestPrivacySanitizer(unittest.TestCase):
    def setUp(self) -> None:
        self.audit_logger = AuditLogger()
        self.sanitizer = PrivacySanitizer(audit_logger=self.audit_logger)

    def test_sanitize_credentials_and_passwords(self) -> None:
        raw_record = {
            "id": "test-cred-001",
            "title": "Account Alert",
            "body": "Your password: SecretPassword123! and token=abc123xyz key: my-api-key",
            "entities": {"app": "TestApp"},
        }
        sanitized = self.sanitizer.sanitize_record(raw_record)
        self.assertNotIn("SecretPassword123!", sanitized["body"])
        self.assertIn("[REDACTED_", sanitized["body"])
        self.assertGreater(self.audit_logger.sanitizations_by_type["credential"], 0)

    def test_sanitize_bearer_jwt_token(self) -> None:
        raw_record = {
            "id": "test-jwt-001",
            "title": "Auth Token",
            "body": "Authorization header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        }
        sanitized = self.sanitizer.sanitize_record(raw_record)
        self.assertNotIn("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", sanitized["body"])
        self.assertIn("Bearer [REDACTED_TOKEN]", sanitized["body"])

    def test_sanitize_credit_card_numbers(self) -> None:
        raw_record = {
            "id": "test-card-001",
            "title": "Payment Made",
            "body": "Charged $100 to card 4532-1234-5678-9012 successfully.",
        }
        sanitized = self.sanitizer.sanitize_record(raw_record)
        self.assertNotIn("4532-1234-5678-9012", sanitized["body"])
        self.assertIn("[REDACTED_CARD]", sanitized["body"])
        self.assertGreater(self.audit_logger.sanitizations_by_type["card"], 0)

    def test_sanitize_unapproved_email_domains(self) -> None:
        raw_record = {
            "id": "test-email-001",
            "title": "New Email",
            "body": "Contact support at user123@privatecompany.com for help.",
            "contains_email": True,
            "entities": {"email_domain": "privatecompany.com"},
        }
        sanitized = self.sanitizer.sanitize_record(raw_record)
        self.assertNotIn("privatecompany.com", sanitized["body"])
        self.assertIn("user123@example.com", sanitized["body"])
        self.assertEqual(sanitized["entities"]["email_domain"], "example.com")
        self.assertGreater(self.audit_logger.sanitizations_by_type["email"], 0)

    def test_sanitize_phone_numbers(self) -> None:
        raw_record = {
            "id": "test-phone-001",
            "title": "Delivery Contact",
            "body": "Call driver at +91-9876543210 or 9876543210.",
        }
        sanitized = self.sanitizer.sanitize_record(raw_record)
        self.assertNotIn("9876543210", sanitized["body"])
        self.assertIn("[REDACTED_PHONE]", sanitized["body"])

    def test_sanitize_national_ids(self) -> None:
        raw_record = {
            "id": "test-id-001",
            "title": "ID Check",
            "body": "Aadhaar number 5432 8765 4321 verified. SSN 123-45-6789.",
        }
        sanitized = self.sanitizer.sanitize_record(raw_record)
        self.assertNotIn("5432 8765 4321", sanitized["body"])
        self.assertNotIn("123-45-6789", sanitized["body"])
        self.assertIn("[REDACTED_NATIONAL_ID]", sanitized["body"])

    def test_sanitize_external_urls(self) -> None:
        raw_record = {
            "id": "test-url-001",
            "title": "Link Shared",
            "body": "Visit https://phishing-site.org/login to reset account.",
        }
        sanitized = self.sanitizer.sanitize_record(raw_record)
        self.assertNotIn("phishing-site.org", sanitized["body"])
        self.assertIn("https://example.com", sanitized["body"])

    def test_validate_privacy_compliance(self) -> None:
        dirty_record = {
            "title": "Leak Test",
            "body": "Password is mySecret123 with card 4532123456789012 and email test@realdomain.org",
        }
        errors = validate_privacy_compliance(dirty_record)
        self.assertTrue(len(errors) >= 3)

        clean_record = {
            "title": "Clean Test",
            "body": "Use 123456 to verify. Visit https://example.com or email user@example.com.",
        }
        clean_errors = validate_privacy_compliance(clean_record)
        self.assertEqual(clean_errors, [])

    def test_fallback_error_recovery(self) -> None:
        class CorruptedDict(dict):
            def __getitem__(self, item: str) -> str:
                if item == "entities":
                    raise RuntimeError("Simulated entity fault")
                return super().__getitem__(item)

        corrupted_record = CorruptedDict({
            "id": "corrupted-001",
            "title": "Test Title",
            "body": "Email user@badsite.com and card 4532123456789012",
            "entities": {},
        })

        # Sanitizer should invoke fallback recovery without crashing
        sanitized = self.sanitizer.sanitize_record(corrupted_record)
        self.assertNotIn("badsite.com", sanitized["body"])
        self.assertGreater(self.audit_logger.sanitizations_by_type["fallback_recovery"], 0)


if __name__ == "__main__":
    unittest.main()
