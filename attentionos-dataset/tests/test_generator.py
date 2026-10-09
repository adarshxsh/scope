from __future__ import annotations

import unittest
from generator import NotificationDatasetGenerator
from validator.privacy import validate_privacy_compliance
from validator.schema import validate_record


class TestNotificationDatasetGenerator(unittest.TestCase):
    def test_generator_privacy_compliance(self) -> None:
        generator = NotificationDatasetGenerator(seed=123, sanitize=True)
        records = list(generator.generate(50))
        self.assertEqual(len(records), 50)

        for record in records:
            schema_errors = validate_record(record)
            self.assertEqual(schema_errors, [], f"Schema validation error in record {record['id']}: {schema_errors}")

            privacy_errors = validate_privacy_compliance(record)
            self.assertEqual(privacy_errors, [], f"Privacy compliance error in record {record['id']}: {privacy_errors}")

        audit = generator.sanitizer.audit_logger.to_dict()
        self.assertEqual(audit["total_scanned"], 50)

    def test_sanitization_disabled_flag(self) -> None:
        generator = NotificationDatasetGenerator(seed=123, sanitize=False)
        records = list(generator.generate(10))
        self.assertEqual(len(records), 10)
        self.assertEqual(generator.sanitizer.audit_logger.total_scanned, 0)


if __name__ == "__main__":
    unittest.main()
