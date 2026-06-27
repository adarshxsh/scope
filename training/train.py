"""CLI entrypoint for the offline AttentionOS training pipeline."""

from __future__ import annotations

import argparse
import os
# Force CPU execution to bypass Apple Silicon tensorflow-metal GPU bugs
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["TF_METAL_DEVICE_THREAD_LIMIT"] = "1"

from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import tensorflow as tf

tf.config.set_visible_devices([], 'GPU')

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



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train the offline AttentionOS look_again_score MLP."
    )
    parser.add_argument(
        "--data",
        type=Path,
        default=Path("attentionos-dataset/output/notifications_100000_seed42.jsonl"),
        help="Path to Flutter-exported JSONL dataset.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("training/runs/latest"),
        help="Output directory for exported artifacts.",
    )
    parser.add_argument("--epochs", type=int, default=TrainingConfig.epochs)
    parser.add_argument("--batch-size", type=int, default=TrainingConfig.batch_size)
    parser.add_argument(
        "--learning-rate", type=float, default=TrainingConfig.learning_rate
    )
    parser.add_argument("--seed", type=int, default=RANDOM_SEED)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    tf.keras.utils.set_random_seed(args.seed)

    output_dir = ensure_dir(args.out)
    export_dir = ensure_dir(output_dir / "export")
    evaluation_dir = ensure_dir(output_dir / "evaluation")

    records = read_jsonl(args.data)
    dataset = build_dataset(records)
    splits = split_dataset(dataset.features, dataset.target, SplitConfig(), args.seed)

    # Calculate mean and variance using numpy to perform direct graph-level normalization
    mean_val = np.mean(splits.x_train, axis=0)
    variance_val = np.var(splits.x_train, axis=0)
    # Avoid division-by-zero overflow in constant folding
    safe_variance = np.where(variance_val < 1e-5, 1.0, variance_val)
    stddev_val = np.sqrt(safe_variance)

    config = TrainingConfig(
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.learning_rate,
    )
    model = build_baseline_mlp(
        mean=mean_val.tolist(),
        stddev=stddev_val.tolist(),
        learning_rate=config.learning_rate,
    )

    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=config.early_stopping_patience,
            min_delta=config.min_delta,
            restore_best_weights=True,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=config.reduce_lr_patience,
            min_lr=1e-6,
        ),
    ]

    history = model.fit(
        splits.x_train,
        splits.y_train,
        validation_data=(splits.x_val, splits.y_val),
        epochs=config.epochs,
        batch_size=config.batch_size,
        callbacks=callbacks,
        verbose=2,
    )

    predictions = model.predict(splits.x_test, batch_size=config.batch_size)
    metrics = regression_metrics(splits.y_test, predictions)

    saved_model_dir = export_saved_model(model, export_dir / "saved_model")
    tflite_path = export_float32_tflite(
        saved_model_dir,
        export_dir / "ghost_ai.tflite",
    )

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
        "dataset_path": str(args.data),
        "sample_count": len(records),
        "feature_vector_size": FEATURE_VECTOR_SIZE,
        "feature_source": "Flutter deterministic FeatureExtractor",
        "python_feature_generation": False,
        "target": "look_again_score",
        "architecture": [
            "Input(63)",
            "Normalization",
            "Dense(128, relu)",
            "Dropout(0.2)",
            "Dense(64, relu)",
            "Dense(32, relu)",
            "Dense(1, look_again_score)",
        ],
        "splits": {
            "train": int(len(splits.x_train)),
            "validation": int(len(splits.x_val)),
            "test": int(len(splits.x_test)),
            "seed": args.seed,
        },
        "normalization": normalization_stats(splits.x_train),
        "metrics": metrics,
        "artifacts": {
            "saved_model": str(saved_model_dir),
            "quantized_tflite": str(tflite_path),
            "label_encoder": str(label_encoder_path),
            "history_csv": str(output_dir / "history.csv"),
            "evaluation_dir": str(evaluation_dir),
        },
        "flutter": {
            "input_dtype": "float32",
            "input_shape": [1, FEATURE_VECTOR_SIZE],
            "output_dtype": "float32",
            "output_shape": [1, 1],
            "output_name": "look_again_score",
        },
    }
    write_json(output_dir / "metadata.json", metadata)

    print(f"SavedModel: {saved_model_dir}")
    print(f"TFLite: {tflite_path}")
    print(f"Metrics: {metrics}")


if __name__ == "__main__":
    main()

