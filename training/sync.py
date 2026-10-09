"""CLI entrypoint and sync bridge to ingest local JSONL feedback datasets, retrain GhostAI MLP models, and deploy versioned TFLite binaries."""

from __future__ import annotations

import argparse
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Force CPU execution to bypass Apple Silicon tensorflow-metal GPU bugs
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["TF_METAL_DEVICE_THREAD_LIMIT"] = "1"

import numpy as np
import tensorflow as tf

tf.config.set_visible_devices([], "GPU")

from training.config import (
    CATEGORICAL_LABELS,
    FEATURE_VECTOR_SIZE,
    RANDOM_SEED,
    SplitConfig,
    TrainingConfig,
)
from training.evaluation.metrics import (
    regression_metrics,
    write_confusion_reports,
    write_history_csv,
)
from training.evaluation.plots import plot_regression_results, plot_training_history
from training.export.tflite_exporter import (
    export_float32_tflite,
    export_saved_model,
)
from training.models.mlp import build_baseline_mlp
from training.utils.io import ensure_dir, read_jsonl, write_json
from training.utils.preprocessing import (
    build_dataset,
    normalization_stats,
    split_dataset,
)


def find_default_feedback_path() -> Path | None:
    candidates = [
        Path("attentionos-dataset/output/feedback_dataset.jsonl"),
        Path("scope/feedback_dataset.jsonl"),
        Path("training/feedback_dataset.jsonl"),
        Path("feedback_dataset.jsonl"),
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync local JSONL feedback logs, retrain GhostAI model, and export TFLite binary."
    )
    parser.add_argument(
        "--feedback-path",
        type=Path,
        default=find_default_feedback_path(),
        help="Path to on-device JSONL feedback dataset.",
    )
    parser.add_argument(
        "--base-data",
        type=Path,
        default=Path("attentionos-dataset/output/notifications_100000_seed42.jsonl"),
        help="Path to base offline JSONL dataset.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("training/runs/synced_model"),
        help="Output directory for synced training artifacts.",
    )
    parser.add_argument(
        "--deploy-dir",
        type=Path,
        default=None,
        help="Target local app storage directory to deploy ghost_ai.tflite binary.",
    )
    parser.add_argument("--epochs", type=int, default=TrainingConfig.epochs)
    parser.add_argument("--batch-size", type=int, default=TrainingConfig.batch_size)
    parser.add_argument(
        "--learning-rate", type=float, default=TrainingConfig.learning_rate
    )
    parser.add_argument("--seed", type=int, default=RANDOM_SEED)
    return parser.parse_args()


def validate_tflite_binary(tflite_path: Path) -> bool:
    """Validates tensor shapes and execution of the compiled TFLite model."""
    if not tflite_path.exists():
        raise FileNotFoundError(f"TFLite binary missing at {tflite_path}")

    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    input_shape = list(input_details[0]["shape"])
    output_shape = list(output_details[0]["shape"])

    expected_input = [1, FEATURE_VECTOR_SIZE]
    expected_output = [1, 1]

    if input_shape != expected_input or output_shape != expected_output:
        raise ValueError(
            f"TFLite model shape validation failed! Expected input {expected_input}, output {expected_output}. "
            f"Got input {input_shape}, output {output_shape}."
        )

    # Test dummy inference
    dummy_input = np.zeros((1, FEATURE_VECTOR_SIZE), dtype=np.float32)
    interpreter.set_tensor(input_details[0]["index"], dummy_input)
    interpreter.invoke()
    _ = interpreter.get_tensor(output_details[0]["index"])

    print(f"Validated TFLite model at {tflite_path}: input {input_shape}, output {output_shape}.")
    return True


def run_sync(
    feedback_path: Path | None = None,
    base_data: Path | None = None,
    out_dir: Path = Path("training/runs/synced_model"),
    deploy_dir: Path | None = None,
    epochs: int = TrainingConfig.epochs,
    batch_size: int = TrainingConfig.batch_size,
    learning_rate: float = TrainingConfig.learning_rate,
    seed: int = RANDOM_SEED,
) -> Path:
    tf.keras.utils.set_random_seed(seed)

    output_dir = ensure_dir(out_dir)
    export_dir = ensure_dir(output_dir / "export")
    evaluation_dir = ensure_dir(output_dir / "evaluation")

    all_records: list[dict[str, Any]] = []

    # 1. Load base dataset if available
    if base_data and base_data.exists():
        print(f"Loading base dataset: {base_data}")
        base_records = read_jsonl(base_data)
        all_records.extend(base_records)

    # 2. Ingest feedback dataset
    feedback_count = 0
    if feedback_path and feedback_path.exists():
        print(f"Ingesting local feedback dataset: {feedback_path}")
        feedback_records = read_jsonl(feedback_path)
        all_records.extend(feedback_records)
        feedback_count = len(feedback_records)
    else:
        print("No feedback dataset found; training solely on base dataset.")

    if not all_records:
        raise ValueError("No records found to perform model sync and training.")

    print(f"Total dataset records for training: {len(all_records)} (Feedback logs: {feedback_count})")

    # 3. Preprocess & build dataset
    dataset = build_dataset(all_records)
    splits = split_dataset(dataset.features, dataset.target, SplitConfig(), seed)

    # 4. Normalize & build model
    mean_val = np.mean(splits.x_train, axis=0)
    variance_val = np.var(splits.x_train, axis=0)
    safe_variance = np.where(variance_val < 1e-5, 1.0, variance_val)
    stddev_val = np.sqrt(safe_variance)

    model = build_baseline_mlp(
        mean=mean_val.tolist(),
        stddev=stddev_val.tolist(),
        learning_rate=learning_rate,
    )

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=TrainingConfig.early_stopping_patience,
            min_delta=TrainingConfig.min_delta,
            restore_best_weights=True,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=TrainingConfig.reduce_lr_patience,
            min_lr=1e-6,
        ),
    ]

    print(f"Training GhostAI model for {epochs} epochs...")
    history = model.fit(
        splits.x_train,
        splits.y_train,
        validation_data=(splits.x_val, splits.y_val),
        epochs=epochs,
        batch_size=batch_size,
        callbacks=callbacks,
        verbose=2,
    )

    predictions = model.predict(splits.x_test, batch_size=batch_size)
    metrics = regression_metrics(splits.y_test, predictions)

    saved_model_dir = export_saved_model(model, export_dir / "saved_model")
    tflite_path = export_float32_tflite(
        saved_model_dir,
        export_dir / "ghost_ai.tflite",
    )

    # 5. Validate output binary integrity and shape
    validate_tflite_binary(tflite_path)

    # 6. Optional deployment step to application storage
    deployed_path: str | None = None
    if deploy_dir:
        deploy_dir_path = ensure_dir(deploy_dir)
        target_file = deploy_dir_path / "ghost_ai.tflite"
        shutil.copy2(tflite_path, target_file)
        deployed_path = str(target_file)
        print(f"Deployed dynamic model binary to app storage: {target_file}")

    write_history_csv(history, output_dir / "history.csv")
    plot_training_history(history, evaluation_dir)
    plot_regression_results(splits.y_test, predictions, evaluation_dir)
    write_json(evaluation_dir / "regression_metrics.json", metrics)

    write_confusion_reports(
        y_true_by_label={},
        y_pred_by_label={},
        encoders={
            key: dataset.label_encoders[key]
            for key in CATEGORICAL_LABELS
            if key in dataset.label_encoders
        },
        output_dir=evaluation_dir / "confusion_reports",
    )

    label_encoder_path = output_dir / "label_encoder.json"
    write_json(label_encoder_path, dataset.label_encoders)

    metadata = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "feedback_path": str(feedback_path) if feedback_path else None,
        "base_data_path": str(base_data) if base_data else None,
        "sample_count": len(all_records),
        "feedback_sample_count": feedback_count,
        "feature_vector_size": FEATURE_VECTOR_SIZE,
        "target": "look_again_score",
        "metrics": metrics,
        "artifacts": {
            "saved_model": str(saved_model_dir),
            "quantized_tflite": str(tflite_path),
            "deployed_tflite": deployed_path,
        },
    }
    write_json(output_dir / "metadata.json", metadata)
    print(f"Sync pipeline complete. Output TFLite binary: {tflite_path}")
    return tflite_path


def main() -> None:
    args = parse_args()
    run_sync(
        feedback_path=args.feedback_path,
        base_data=args.base_data,
        out_dir=args.out,
        deploy_dir=args.deploy_dir,
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.learning_rate,
        seed=args.seed,
    )


if __name__ == "__main__":
    main()
