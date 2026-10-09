import json
import tempfile
import unittest
from pathlib import Path

from training.sync import run_sync, validate_tflite_binary


class TestTrainingSync(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)

        # Create dummy feedback dataset
        self.feedback_file = self.temp_path / "feedback.jsonl"
        dummy_records = []
        for i in range(15):
            dummy_records.append({
                "id": f"notif_{i}",
                "timestamp": 1700000000000 + i,
                "title": f"Test Title {i}",
                "content": f"Test Content Body {i}",
                "packageName": "com.example.app",
                "feedbackType": "reward" if i % 2 == 0 else "correction",
                "userFeedback": "+1" if i % 2 == 0 else "correction",
                "category": "msg" if i % 2 == 0 else "financial",
                "priority": "medium" if i % 2 == 0 else "critical",
                "look_again_score": 0.5 if i % 2 == 0 else 1.0,
                "features": [float(x) for x in range(63)],
                "labels": {
                    "category_class": "msg" if i % 2 == 0 else "financial",
                    "urgency": "medium" if i % 2 == 0 else "critical",
                    "look_again_score": 0.5 if i % 2 == 0 else 1.0,
                },
            })

        with self.feedback_file.open("w", encoding="utf-8") as f:
            for rec in dummy_records:
                f.write(json.dumps(rec) + "\n")

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_run_sync_with_feedback(self):
        out_dir = self.temp_path / "runs" / "synced"
        deploy_dir = self.temp_path / "app_docs"

        tflite_path = run_sync(
            feedback_path=self.feedback_file,
            base_data=None,
            out_dir=out_dir,
            deploy_dir=deploy_dir,
            epochs=1,
            batch_size=4,
            seed=42,
        )

        self.assertTrue(tflite_path.exists())
        self.assertTrue(validate_tflite_binary(tflite_path))

        # Verify deployed file
        deployed_file = deploy_dir / "ghost_ai.tflite"
        self.assertTrue(deployed_file.exists())

        # Verify metadata
        metadata_file = out_dir / "metadata.json"
        self.assertTrue(metadata_file.exists())
        with metadata_file.open("r", encoding="utf-8") as f:
            meta = json.load(f)
            self.assertEqual(meta["feedback_sample_count"], 15)


if __name__ == "__main__":
    unittest.main()
