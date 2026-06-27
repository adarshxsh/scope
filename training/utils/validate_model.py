"""Model validation script to calculate MAE, RMSE, R2, avg inference latency, and wrong predictions."""

from __future__ import annotations

import argparse
import os
# Force CPU execution to bypass Apple Silicon tensorflow-metal GPU bugs
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["TF_METAL_DEVICE_THREAD_LIMIT"] = "1"

import time
import json
from pathlib import Path

import numpy as np
import tensorflow as tf

tf.config.set_visible_devices([], 'GPU')

from training.utils.preprocessing import build_dataset
from training.utils.io import read_jsonl, write_json


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the Ghost AI TFLite model.")
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("runs/experiment1/export/ghost_ai.tflite"),
        help="Path to the TFLite model.",
    )
    parser.add_argument(
        "--data",
        type=Path,
        default=Path("attentionos-dataset/output/notifications_100000_seed42.jsonl"),
        help="Path to the validation dataset (JSONL).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("runs/experiment1/validation_report.md"),
        help="Path to write the output markdown report.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    if not args.model.exists():
        raise FileNotFoundError(f"Model not found at {args.model}")
    if not args.data.exists():
        raise FileNotFoundError(f"Dataset not found at {args.data}")

    print(f"Loading dataset: {args.data}")
    records = read_jsonl(args.data)
    
    print("Preprocessing and extracting features...")
    dataset = build_dataset(records)
    x = dataset.features
    y_true = dataset.target.flatten()

    print(f"Loading TFLite model: {args.model}")
    interpreter = tf.lite.Interpreter(model_path=str(args.model))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    input_index = input_details[0]["index"]
    output_index = output_details[0]["index"]

    print("Running inference and measuring latency...")
    latencies = []
    y_pred = []

    # Run inference individually to simulate real-world on-device latency
    total_samples = len(x)
    for i in range(total_samples):
        sample_input = x[i : i + 1].astype(np.float32)

        start_time = time.perf_counter()
        interpreter.set_tensor(input_index, sample_input)
        interpreter.invoke()
        pred = interpreter.get_tensor(output_index)[0][0]
        end_time = time.perf_counter()

        latencies.append((end_time - start_time) * 1000.0)  # ms
        y_pred.append(pred)

        if (i + 1) % 20000 == 0 or i + 1 == total_samples:
            print(f"Processed {i + 1}/{total_samples} samples...")

    y_pred = np.array(y_pred)
    errors = np.abs(y_true - y_pred)

    # Metrics
    mae = float(np.mean(errors))
    mse = float(np.mean((y_true - y_pred) ** 2))
    rmse = float(np.sqrt(mse))
    
    # R2
    y_true_mean = np.mean(y_true)
    ss_res = np.sum((y_true - y_pred) ** 2)
    ss_tot = np.sum((y_true - y_true_mean) ** 2)
    r2 = float(1.0 - (ss_res / ss_tot) if ss_tot > 0 else 0.0)

    avg_latency = float(np.mean(latencies))
    p95_latency = float(np.percentile(latencies, 95))
    
    # Wrong predictions (> 30 points)
    wrong_mask = errors > 30.0
    wrong_count = int(np.sum(wrong_mask))
    wrong_percentage = (wrong_count / total_samples) * 100.0

    # Build worst predictions list
    worst_indices = np.argsort(errors)[::-1][:100]
    worst_predictions = []
    for rank, idx in enumerate(worst_indices, start=1):
        rec = records[idx]
        worst_predictions.append({
            "rank": rank,
            "id": rec.get("id"),
            "app_name": rec.get("app_name"),
            "title": rec.get("title"),
            "body": rec.get("body"),
            "expected": float(y_true[idx]),
            "predicted": float(y_pred[idx]),
            "error": float(errors[idx]),
        })

    # Write worst predictions details to JSON for manual review
    worst_json_path = args.out.parent / "worst_100_predictions.json"
    write_json(worst_json_path, worst_predictions)

    # Prepare markdown report
    report = []
    report.append("# Ghost AI Model Validation Report")
    report.append("")
    report.append(f"**Model Path:** `{args.model}`")
    report.append(f"**Dataset Path:** `{args.data}`")
    report.append(f"**Total Samples:** {total_samples:,}")
    report.append("")
    report.append("## Core Metrics")
    report.append("")
    report.append("| Metric | Result | Description |")
    report.append("| :--- | :--- | :--- |")
    report.append(f"| **MAE** | `{mae:.2f}` | Mean Absolute Error |")
    report.append(f"| **RMSE** | `{rmse:.2f}` | Root Mean Squared Error |")
    report.append(f"| **R²** | `{r2:.2f}` | Coefficient of Determination |")
    report.append(f"| **Avg Inference Time** | `{avg_latency:.3f} ms` | Average time per single inference |")
    report.append(f"| **95th percentile Latency** | `{p95_latency:.3f} ms` | 95% of inferences are faster than this |")
    report.append(f"| **Wrong predictions (>30 pts)** | `{wrong_count:,} ({wrong_percentage:.2f}%)` | Count & % of predictions with error > 30 |")
    report.append("")
    report.append("## Worst 100 Predictions (Top 10)")
    report.append("")
    report.append("| Rank | App Name | Title | Body | Expected | Predicted | Absolute Error |")
    report.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- |")
    for wp in worst_predictions[:10]:
        body_truncated = wp["body"][:40] + "..." if len(wp["body"]) > 40 else wp["body"]
        report.append(
            f"| {wp['rank']} | {wp['app_name']} | {wp['title']} | {body_truncated} | {wp['expected']:.1f} | {wp['predicted']:.1f} | {wp['error']:.1f} |"
        )
    report.append("")
    report.append(f"Detailed worst 100 predictions written to: [`worst_100_predictions.json`](file://{worst_json_path})")

    # Save Markdown report
    args.out.write_text("\n".join(report), encoding="utf-8")
    print(f"\nReport written to: {args.out}")

    print("\nCore Results Summary:")
    print(f"MAE: {mae:.2f}")
    print(f"RMSE: {rmse:.2f}")
    print(f"R2: {r2:.2f}")
    print(f"Avg Inference: {avg_latency:.3f} ms")
    print(f"Wrong predictions (>30 pts): {wrong_count:,} ({wrong_percentage:.2f}%)")


if __name__ == "__main__":
    main()
