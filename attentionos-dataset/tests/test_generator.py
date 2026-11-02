from __future__ import annotations

import unittest
from generator import NotificationDatasetGenerator
from validator.schema import validate_record
from validator.statistics import summarize


class TestDatasetGenerator(unittest.TestCase):
    def test_generator_produces_sanitized_records(self) -> None:
        generator = NotificationDatasetGenerator(seed=123, enable_sanitization=True)
        records = list(generator.generate(50))

        self.assertEqual(len(records), 50)
        for record in records:
            self.assertTrue(record.get("privacy_sanitized"))
            errors = validate_record(record, check_privacy=True)
            self.assertEqual(
                errors,
                [],
                f"Record {record.get('id')} failed validation: {errors}",
            )

    def test_generator_statistics_summary(self) -> None:
        generator = NotificationDatasetGenerator(seed=456, enable_sanitization=True)
        records = list(generator.generate(30))
        stats = summarize(records)

        self.assertEqual(stats["total"], 30)
        self.assertEqual(stats["privacy_sanitized_count"], 30)
        self.assertEqual(stats["privacy_leaks_count"], 0)


if __name__ == "__main__":
    unittest.main()
