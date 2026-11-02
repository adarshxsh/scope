from __future__ import annotations

import unittest
from validator.privacy import check_privacy_leaks
from validator.schema import validate_record


class TestPrivacyValidator(unittest.TestCase):
    def test_check_privacy_leaks_detects_raw_pii(self) -> None:
        leaky_record = {
            "title": "Order confirmed",
            "body": "Order OD123456 placed for ₹1500. Contact user@example.com",
            "entities": {"amount": 1500},
        }
        leaks = check_privacy_leaks(leaky_record)
        self.assertGreater(len(leaks), 0)
        self.assertTrue(any("email" in err for err in leaks))
        self.assertTrue(any("order" in err for err in leaks))
        self.assertTrue(any("amount" in err for err in leaks))

    def test_check_privacy_leaks_passes_clean_record(self) -> None:
        clean_record = {
            "title": "Order confirmed",
            "body": "Order [ORDER_ID] placed for ₹[AMOUNT]. Contact [EMAIL]",
            "entities": {"amount": "[AMOUNT]"},
            "privacy_sanitized": True,
        }
        leaks = check_privacy_leaks(clean_record)
        self.assertEqual(len(leaks), 0)

    def test_validate_record_integrates_privacy_check(self) -> None:
        leaky_full_record = {
            "id": "uuid-1234",
            "app_name": "TestApp",
            "package_name": "com.test.app",
            "category": "Shopping",
            "subcategory": "E-commerce",
            "notification_type": "order_placed",
            "title": "Order OD999888 confirmed",
            "body": "Your order OD999888 of ₹2500 is placed.",
            "language": "en",
            "requires_action": False,
            "intent": "track",
            "android": {"importance": 3},
            "priority_score": 50,
            "priority": "medium",
            "look_again_score": 50,
            "look_again": False,
            "labels": {},
        }
        errors = validate_record(leaky_full_record, check_privacy=True)
        self.assertGreater(len(errors), 0)
        self.assertTrue(any("order" in err for err in errors))


if __name__ == "__main__":
    unittest.main()
