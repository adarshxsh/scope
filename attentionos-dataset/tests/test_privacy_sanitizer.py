from __future__ import annotations

import unittest
from privacy.sanitizer import PrivacySanitizer


class TestPrivacySanitizer(unittest.TestCase):
    def setUp(self) -> None:
        self.sanitizer = PrivacySanitizer()

    def test_sanitize_text_pii_entities(self) -> None:
        raw_text = "Received ₹15499 from Rahul. Order #OD987654. Contact test@example.com or +91 9876543210. OTP 123456."
        ctx = {"person": "Rahul", "order_id": "OD987654", "email": "test@example.com", "otp": "123456"}
        sanitized = self.sanitizer.sanitize_text(raw_text, ctx=ctx)

        self.assertNotIn("15499", sanitized)
        self.assertNotIn("Rahul", sanitized)
        self.assertNotIn("OD987654", sanitized)
        self.assertNotIn("test@example.com", sanitized)
        self.assertNotIn("9876543210", sanitized)
        self.assertIn("[AMOUNT]", sanitized)
        self.assertIn("[NAME]", sanitized)
        self.assertIn("[ORDER_ID]", sanitized)
        self.assertIn("[EMAIL]", sanitized)
        self.assertIn("[PHONE]", sanitized)

    def test_sanitize_text_without_context(self) -> None:
        raw_text = "Your refund of ₹1250 for order OD123456 has been processed. Email user@domain.com."
        sanitized = self.sanitizer.sanitize_text(raw_text)

        self.assertNotIn("1250", sanitized)
        self.assertNotIn("OD123456", sanitized)
        self.assertNotIn("user@domain.com", sanitized)
        self.assertIn("[AMOUNT]", sanitized)
        self.assertIn("[ORDER_ID]", sanitized)
        self.assertIn("[EMAIL]", sanitized)

    def test_sanitize_entities(self) -> None:
        entities = {
            "amount": 4299,
            "merchant": "FreshMart",
            "reference_id": "10001234",
            "user_email": "user@test.org",
        }
        sanitized = self.sanitizer.sanitize_entities(entities)

        self.assertEqual(sanitized["amount"], "[AMOUNT]")
        self.assertEqual(sanitized["reference_id"], "[REF_ID]")
        self.assertNotIn("user@test.org", sanitized["user_email"])

    def test_sanitize_record(self) -> None:
        record = {
            "id": "test-uuid-1234",
            "title": "Payment received from Priya",
            "body": "₹500 received via UPI ref 88776655.",
            "entities": {"amount": 500, "reference_id": "88776655"},
        }
        ctx = {"person": "Priya", "ref": "88776655"}
        sanitized_rec = self.sanitizer.sanitize_record(record, ctx=ctx)

        self.assertTrue(sanitized_rec.get("privacy_sanitized"))
        self.assertNotIn("Priya", sanitized_rec["title"])
        self.assertNotIn("500", sanitized_rec["body"])
        self.assertNotIn("88776655", sanitized_rec["body"])

    def test_edge_cases_and_graceful_recovery(self) -> None:
        self.assertEqual(self.sanitizer.sanitize_text(""), "")
        self.assertEqual(self.sanitizer.sanitize_text(None), "")
        self.assertEqual(self.sanitizer.sanitize_entities(None), {})
        self.assertEqual(self.sanitizer.sanitize_record(None), {})

        # Record with missing fields or malformed data
        malformed = {"title": None, "body": 12345, "entities": "not_a_dict"}
        sanitized = self.sanitizer.sanitize_record(malformed)
        self.assertTrue(sanitized.get("privacy_sanitized"))


if __name__ == "__main__":
    unittest.main()
