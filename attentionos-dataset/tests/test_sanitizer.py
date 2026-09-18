from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

from export.sanitizer import PrivacySanitizer
from generator import NotificationDatasetGenerator


def test_pii_redaction_names_emails_orders_otps():
    sanitizer = PrivacySanitizer(enabled=True, perturbation_bound=0.1, seed=42)

    # Record with name, email, order ID, phone, ref ID
    sample_record = {
        "id": "test-1",
        "title": "Order confirmed for Harsh",
        "body": "Package #OD987654 for ₹1500 shipped with Fariq. Email harsh@example.com or call +91 9876543210. Ref 12345678.",
        "category": "Shopping",
        "intent": "track",
        "urgency": "medium",
        "look_again_score": 0.45,
        "entities": {
            "order_id": "OD987654",
            "reference_id": "12345678",
            "amount": 1500,
        },
        "android": {
            "timestamp": "2026-06-26T09:00:00+00:00",
            "importance": 3,
        },
    }

    sanitized = sanitizer.sanitize(sample_record)

    # Verify PII placeholders
    assert "<NAME>" in sanitized["title"] or "<NAME>" in sanitized["body"]
    assert "<ORDER_ID>" in sanitized["body"]
    assert "<EMAIL>" in sanitized["body"]
    assert "<PHONE>" in sanitized["body"]
    assert "<REF_ID>" in sanitized["body"]

    # Verify no raw unmasked email/phone/order ID
    assert "harsh@example.com" not in sanitized["body"]
    assert "+91 9876543210" not in sanitized["body"]
    assert "OD987654" not in sanitized["body"]

    # Verify entities
    assert sanitized["entities"]["order_id"] == "<ORDER_ID>"
    assert sanitized["entities"]["reference_id"] == "<REF_ID>"


def test_otp_redaction():
    sanitizer = PrivacySanitizer(enabled=True, perturbation_bound=0.1, seed=42)

    sample_record = {
        "id": "test-otp",
        "title": "OTP Verification",
        "body": "Use 882715 to verify your sign-in. Valid for 10 minutes.",
        "category": "OTP",
        "intent": "verify",
        "urgency": "high",
        "look_again_score": 0.95,
        "entities": {
            "otp_length": 6,
        },
    }

    sanitized = sanitizer.sanitize(sample_record)
    assert "<OTP>" in sanitized["body"]
    assert "882715" not in sanitized["body"]


def test_financial_amount_perturbation():
    sanitizer = PrivacySanitizer(enabled=True, perturbation_bound=0.1, seed=42)

    sample_record = {
        "id": "test-amount",
        "title": "Payment received",
        "body": "₹5000 received from Riya. Balance updated.",
        "category": "UPI",
        "intent": "inform",
        "urgency": "low",
        "look_again_score": 0.2,
        "entities": {
            "amount": 5000,
        },
    }

    sanitized = sanitizer.sanitize(sample_record)

    # Verify amount was perturbed
    assert "₹5000" not in sanitized["body"]
    assert "₹" in sanitized["body"]
    assert sanitized["entities"]["amount"] != 5000
    # Check bounded within 10%
    assert 4500 <= sanitized["entities"]["amount"] <= 5500


def test_structural_labels_preservation():
    sanitizer = PrivacySanitizer(enabled=True, perturbation_bound=0.1, seed=42)

    sample_record = {
        "id": "test-labels",
        "title": "Dr. Smith appointment",
        "body": "Appointment with Dr. Smith at 10:00 AM.",
        "category": "Healthcare",
        "intent": "attend",
        "urgency": "high",
        "look_again_score": 0.85,
        "requires_action": True,
        "labels": {
            "category_class": "Healthcare",
            "intent": "attend",
            "urgency": "high",
            "requires_action": True,
            "look_again_score": 0.85,
        },
    }

    sanitized = sanitizer.sanitize(sample_record)

    # Verify structural classification labels are unchanged
    assert sanitized["category"] == "Healthcare"
    assert sanitized["intent"] == "attend"
    assert sanitized["urgency"] == "high"
    assert sanitized["look_again_score"] == 0.85
    assert sanitized["labels"]["category_class"] == "Healthcare"
    assert sanitized["labels"]["intent"] == "attend"
    assert sanitized["labels"]["urgency"] == "high"
    assert sanitized["labels"]["look_again_score"] == 0.85


def test_sanitizer_disabled():
    sanitizer = PrivacySanitizer(enabled=False)

    sample_record = {
        "id": "test-disabled",
        "title": "Order OD123456",
        "body": "Call +91 9876543210 for harsh@example.com",
    }

    sanitized = sanitizer.sanitize(sample_record)
    assert sanitized["title"] == "Order OD123456"
    assert sanitized["body"] == "Call +91 9876543210 for harsh@example.com"


def test_all_scenarios_dataset_generation_sanitization():
    generator = NotificationDatasetGenerator(seed=123)
    raw_records = list(generator.generate(100))

    sanitizer = PrivacySanitizer(enabled=True, perturbation_bound=0.1, seed=123)
    sanitized_records = list(sanitizer.sanitize_stream(raw_records))

    assert len(sanitized_records) == 100

    for raw, sanitized in zip(raw_records, sanitized_records):
        # Labels preserved
        assert sanitized["category"] == raw["category"]
        assert sanitized["intent"] == raw["intent"]
        assert sanitized["urgency"] == raw["urgency"]
        assert sanitized["look_again_score"] == raw["look_again_score"]

        # No unmasked emails
        assert "@example.com" not in sanitized["body"]
        assert "@example.com" not in sanitized["title"]


def test_offline_training_pipeline_with_sanitized_export():
    with tempfile.TemporaryDirectory() as tmpdir:
        dataset_path = Path(tmpdir) / "sanitized_dataset.jsonl"
        output_dir = Path(tmpdir) / "train_output"

        # 1. Generate dataset using CLI generate.py
        cmd_gen = [
            sys.executable,
            str(Path(__file__).resolve().parents[1] / "generate.py"),
            "--count", "1000",
            "--output", str(dataset_path),
            "--sanitize",
            "--perturbation-bound", "0.1",
        ]
        res_gen = subprocess.run(cmd_gen, capture_output=True, text=True)
        assert res_gen.returncode == 0, f"Generator failed: {res_gen.stderr}"
        assert dataset_path.exists()

        # Check exported records contain PII placeholders
        with dataset_path.open("r", encoding="utf-8") as f:
            lines = [json.loads(line) for line in f if line.strip()]
            assert len(lines) == 1000
            content_str = dataset_path.read_text(encoding="utf-8")
            assert "<NAME>" in content_str or "<ORDER_ID>" in content_str or "<EMAIL>" in content_str

        # 2. Run training script on sanitized dataset
        train_script = Path(__file__).resolve().parents[2] / "training" / "train.py"
        cmd_train = [
            sys.executable,
            str(train_script),
            "--data", str(dataset_path),
            "--out", str(output_dir),
            "--epochs", "2",
        ]
        env = dict(PYTHONPATH=str(Path(__file__).resolve().parents[2]))
        res_train = subprocess.run(cmd_train, capture_output=True, text=True, env=env)
        assert res_train.returncode == 0, f"Train script failed: {res_train.stderr}\nOutput: {res_train.stdout}"

        # Verify output TFLite model produced
        tflite_model = output_dir / "export" / "ghost_ai.tflite"
        assert tflite_model.exists()
