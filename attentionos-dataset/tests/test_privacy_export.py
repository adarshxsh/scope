from __future__ import annotations

import json
import tempfile
import time
import unittest
from pathlib import Path

from export.csv import write_csv
from export.jsonl import write_jsonl
from export.pii import laplace_noise, perturb_score, process_record_privacy, redact_pii_text
from generator import NotificationDatasetGenerator


class TestPrivacyExport(unittest.TestCase):
    def test_redact_pii_text_names(self) -> None:
        sample_1 = "₹1250 received from Arjun. UPI ref 87654321."
        redacted_1 = redact_pii_text(sample_1)
        self.assertNotIn("Arjun", redacted_1)
        self.assertIn("[NAME]", redacted_1)

        sample_2 = "Appointment with Dr. Sharma at 10:00 AM."
        redacted_2 = redact_pii_text(sample_2)
        self.assertNotIn("Sharma", redacted_2)
        self.assertIn("[NAME]", redacted_2)

        sample_3 = "Riya sent an email with a PDF."
        redacted_3 = redact_pii_text(sample_3)
        self.assertNotIn("Riya", redacted_3)
        self.assertIn("[NAME]", redacted_3)

    def test_redact_pii_text_credit_cards_and_accounts(self) -> None:
        sample_1 = "Card ending 4321 spent ₹499 at FreshMart."
        redacted_1 = redact_pii_text(sample_1)
        self.assertNotIn("4321", redacted_1)
        self.assertIn("[CREDIT_CARD]", redacted_1)

        sample_2 = "A debit of ₹2499 was made from A/c 8765 at BlueKart."
        redacted_2 = redact_pii_text(sample_2)
        self.assertNotIn("8765", redacted_2)
        self.assertIn("[ACCOUNT_NUMBER]", redacted_2)

        sample_3 = "4532 1234 5678 9012 charged ₹1500 at UrbanCart"
        redacted_3 = redact_pii_text(sample_3)
        self.assertNotIn("4532 1234 5678 9012", redacted_3)
        self.assertIn("[CREDIT_CARD]", redacted_3)

    def test_laplace_noise_and_score_perturbation(self) -> None:
        noise_samples = [laplace_noise(scale=1.0) for _ in range(100)]
        self.assertTrue(any(n != 0 for n in noise_samples))

        raw_score = 75.0
        perturbed = perturb_score(raw_score, epsilon=1.0)
        self.assertGreaterEqual(perturbed, 0.0)
        self.assertLessEqual(perturbed, 100.0)
        self.assertIsInstance(perturbed, float)

    def test_process_record_privacy(self) -> None:
        record = {
            "title": "Payment received from Arjun",
            "body": "₹500 received from Arjun on card ending 1234. A/c ending 5678.",
            "review_score": 80,
            "priority_score": 80,
            "look_again_score": 90,
            "priority_reason": "type=payment; from Arjun",
        }

        processed = process_record_privacy(record, redact_pii=True, perturb_scores=True, epsilon=1.0)
        self.assertNotIn("Arjun", processed["title"])
        self.assertNotIn("Arjun", processed["body"])
        self.assertNotIn("1234", processed["body"])
        self.assertNotIn("5678", processed["body"])

        self.assertIn("[NAME]", processed["title"])
        self.assertIn("[CREDIT_CARD]", processed["body"])
        self.assertIn("[ACCOUNT_NUMBER]", processed["body"])

        self.assertLessEqual(len(processed["title"]), 50)
        self.assertLessEqual(len(processed["body"]), 140)

        self.assertNotEqual(processed["review_score"], record["review_score"])

    def test_jsonl_export_privacy(self) -> None:
        generator = NotificationDatasetGenerator(seed=42)
        records = list(generator.generate(50))

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "test.jsonl"
            written = write_jsonl(out_file, records, redact_pii=True, perturb_scores=True, epsilon=1.0)
            self.assertEqual(written, 50)

            lines = out_file.read_text(encoding="utf-8").strip().split("\n")
            self.assertEqual(len(lines), 50)

            for line in lines:
                rec = json.loads(line)
                self.assertIn("review_score", rec)
                title = rec["title"]
                body = rec["body"]

                # Ensure no raw synthetic names or credit card numbers remain
                for unredacted in ["Arjun", "Riya", "Nisha", "Karan", "Meera"]:
                    self.assertNotIn(unredacted, title)
                    self.assertNotIn(unredacted, body)

    def test_csv_export_privacy(self) -> None:
        generator = NotificationDatasetGenerator(seed=42)
        records = list(generator.generate(20))

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "test.csv"
            written = write_csv(out_file, records, redact_pii=True, perturb_scores=True, epsilon=1.0)
            self.assertEqual(written, 20)

            content = out_file.read_text(encoding="utf-8")
            self.assertIn("review_score", content)

    def test_throughput_performance(self) -> None:
        generator = NotificationDatasetGenerator(seed=123)
        count = 2000
        records = list(generator.generate(count))

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = Path(tmpdir) / "bench.jsonl"
            start_time = time.perf_counter()
            written = write_jsonl(out_file, records, redact_pii=True, perturb_scores=True, epsilon=1.0)
            duration = time.perf_counter() - start_time

            self.assertEqual(written, count)
            throughput = count / duration
            print(f"Export throughput: {throughput:.2f} records/sec (time: {duration:.4f}s)")
            self.assertGreater(throughput, 1000.0, f"Throughput {throughput:.2f} rec/s is less than 1,000 rec/s")


if __name__ == "__main__":
    unittest.main()
