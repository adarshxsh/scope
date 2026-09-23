import hashlib
import json
from pathlib import Path
import tempfile
import pytest

from export.jsonl import write_jsonl
from export.csv import write_csv
from generator.base import sanitize_text, NotificationDatasetGenerator, Scenario
from validator.schema import validate_record
from training.dataset.loader import load_jsonl_dataset
from training.export.tflite_exporter import export_evaluation_metrics
from training.utils.io import read_jsonl, write_sha256_sidecar, verify_sha256_sidecar


def sample_records():
    return [
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "app_name": "Google Pay",
            "package_name": "com.google.android.apps.nbu.paisa.user",
            "category": "UPI",
            "subcategory": "UPI",
            "notification_type": "payment_received",
            "title": "Payment received",
            "body": "₹500 received from Rahul.",
            "language": "en",
            "requires_action": False,
            "intent": "inform",
            "android": {"importance": 4},
            "priority_score": 75,
            "priority": "high",
            "look_again_score": 80,
            "look_again": True,
            "labels": {"is_promotion": False},
        }
    ]


def test_jsonl_and_csv_export_sidecars():
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        records = sample_records()

        jsonl_file = tmp_path / "test_data.jsonl"
        count = write_jsonl(jsonl_file, records)
        assert count == 1
        assert jsonl_file.exists()
        jsonl_sidecar = tmp_path / "test_data.jsonl.sha256"
        assert jsonl_sidecar.exists()

        computed_jsonl_hash = hashlib.sha256(jsonl_file.read_bytes()).hexdigest().lower()
        sidecar_hash = jsonl_sidecar.read_text().strip().split()[0].lower()
        assert computed_jsonl_hash == sidecar_hash

        csv_file = tmp_path / "test_data.csv"
        csv_count = write_csv(csv_file, records)
        assert csv_count == 1
        assert csv_file.exists()
        csv_sidecar = tmp_path / "test_data.csv.sha256"
        assert csv_sidecar.exists()

        computed_csv_hash = hashlib.sha256(csv_file.read_bytes()).hexdigest().lower()
        csv_sidecar_hash = csv_sidecar.read_text().strip().split()[0].lower()
        assert computed_csv_hash == csv_sidecar_hash


def test_dataset_loader_verification():
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        records = sample_records()
        jsonl_file = tmp_path / "dataset.jsonl"
        write_jsonl(jsonl_file, records)

        # 1. Valid loading
        loaded = load_jsonl_dataset(jsonl_file)
        assert len(loaded) == 1
        assert loaded[0]["id"] == records[0]["id"]

        # 2. Missing sidecar error
        sidecar_file = tmp_path / "dataset.jsonl.sha256"
        sidecar_file.unlink()
        with pytest.raises(ValueError, match="Checksum sidecar missing"):
            load_jsonl_dataset(jsonl_file)

        # 3. Corrupted dataset error
        sidecar_file.write_text("0" * 64 + "\n", encoding="utf-8")
        with pytest.raises(ValueError, match="Checksum mismatch"):
            load_jsonl_dataset(jsonl_file)


def test_tflite_and_eval_exporter_sidecars():
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        eval_metrics = {"mse": 0.05, "mae": 0.1}
        metrics_file = tmp_path / "regression_metrics.json"

        export_evaluation_metrics(eval_metrics, metrics_file)
        assert metrics_file.exists()
        sidecar = tmp_path / "regression_metrics.json.sha256"
        assert sidecar.exists()

        computed_hash = hashlib.sha256(metrics_file.read_bytes()).hexdigest().lower()
        assert sidecar.read_text().strip().split()[0].lower() == computed_hash


def test_sanitize_text():
    raw_with_html = "<b>Warning:</b> <script>alert('xss')</script> Your account balance is low."
    sanitized_html = sanitize_text(raw_with_html)
    assert "<" not in sanitized_html
    assert ">" not in sanitized_html
    assert sanitized_html == "Warning: alert('xss') Your account balance is low."

    raw_with_control = "Hello\x00\x07World!\x1f"
    sanitized_control = sanitize_text(raw_with_control)
    assert sanitized_control == "HelloWorld!"

    raw_whitespace = "   Lots   of   spaces   "
    assert sanitize_text(raw_whitespace) == "Lots of spaces"


def test_ollama_sanitization_and_validation():
    generator = NotificationDatasetGenerator(seed=42)

    scenario = Scenario(
        category="UPI",
        subcategory="UPI",
        notification_type="payment_received",
        intent="inform",
        title_templates=("Title",),
        body_templates=("Body",),
    )
    ctx = {
        "app_context": "Google Pay",
        "amount": 100,
        "person": "Rahul",
        "ref": "12345",
    }

    # Test when Ollama returns raw text with HTML / control chars
    class MockOllamaResponse:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def read(self):
            payload = {
                "response": json.dumps({
                    "title": "<b>Payment</b>\x00 Received!",
                    "body": "You received ₹100 from Rahul. <script>bad()</script>",
                })
            }
            return json.dumps(payload).encode("utf-8")

    import urllib.request
    original_urlopen = urllib.request.urlopen

    try:
        urllib.request.urlopen = lambda req, timeout=None: MockOllamaResponse()
        generator.use_ollama = True

        res = generator._ollama_notification(scenario, ctx)
        assert res is not None
        title, body = res
        assert "<" not in title and "\x00" not in title
        assert "<" not in body
        assert title == "Payment Received!"
        assert body == "You received ₹100 from Rahul. bad()"
    finally:
        urllib.request.urlopen = original_urlopen
