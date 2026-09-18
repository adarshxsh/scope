"""Model validation script to calculate MAE, RMSE, R2, avg inference latency, and tensor shape contracts."""

from __future__ import annotations

import argparse
import os
# Force CPU execution to bypass Apple Silicon tensorflow-metal GPU bugs
os.environ["CUDA_VISIBLE_DEVICES"] = ""
os.environ["TF_METAL_DEVICE_THREAD_LIMIT"] = "1"

import json
import time
from pathlib import Path
from typing import Any

import numpy as np
import tensorflow as tf

tf.config.set_visible_devices([], "GPU")

from training.utils.io import read_jsonl, write_json
from training.utils.preprocessing import build_dataset


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate the Ghost AI TFLite model.")
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("runs/latest/export/ghost_ai.tflite"),
        help="Path to the quantized TFLite model.",
    )
    parser.add_argument(
        "--baseline",
        type=Path,
        default=None,
        help="Path to the baseline unquantized float32 TFLite model.",
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
        default=Path("runs/latest/validation_report.md"),
        help="Path to write the output markdown report.",
    )
    return parser.parse_args()


def evaluate_tflite_model(model_path: Path, x: np.ndarray, y_true: np.ndarray) -> dict[str, Any]:
    if not model_path.exists():
        raise FileNotFoundError(f"Model not found at {model_path}")

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    input_index = input_details[0]["index"]
    output_index = output_details[0]["index"]

    input_shape = list(input_details[0]["shape"])
    input_shape_sig = list(input_details[0].get("shape_signature", []))
    output_shape = list(output_details[0]["shape"])
    output_shape_sig = list(output_details[0].get("shape_signature", []))

    latencies = []
    y_pred = []
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

    y_pred_arr = np.array(y_pred)
    errors = np.abs(y_true - y_pred_arr)

    mae = float(np.mean(errors))
    mse = float(np.mean((y_true - y_pred_arr) ** 2))
    rmse = float(np.sqrt(mse))

    y_true_mean = np.mean(y_true)
    ss_res = np.sum((y_true - y_pred_arr) ** 2)
    ss_tot = np.sum((y_true - y_true_mean) ** 2)
    r2 = float(1.0 - (ss_res / ss_tot) if ss_tot > 0 else 0.0)

    avg_latency = float(np.mean(latencies))
    p95_latency = float(np.percentile(latencies, 95))

    wrong_mask = errors > 30.0
    wrong_count = int(np.sum(wrong_mask))
    wrong_percentage = (wrong_count / total_samples) * 100.0

    size_bytes = model_path.stat().st_size

    return {
        "model_path": model_path,
        "size_bytes": size_bytes,
        "input_shape": input_shape,
        "input_shape_sig": input_shape_sig,
        "output_shape": output_shape,
        "output_shape_sig": output_shape_sig,
        "input_dtype": str(input_details[0]["dtype"]),
        "output_dtype": str(output_details[0]["dtype"]),
        "mae": mae,
        "rmse": rmse,
        "r2": r2,
        "avg_latency_ms": avg_latency,
        "p95_latency_ms": p95_latency,
        "wrong_count": wrong_count,
        "wrong_percentage": wrong_percentage,
        "y_pred": y_pred_arr,
        "errors": errors,
    }


def main() -> None:
    args = parse_args()

    if not args.model.exists():
        raise FileNotFoundError(f"Quantized model not found at {args.model}")
    if not args.data.exists():
        raise FileNotFoundError(f"Dataset not found at {args.data}")

    # Auto-detect baseline float32 model if not provided
    baseline_path = args.baseline
    if baseline_path is None:
        candidate = args.model.parent / "ghost_ai_float32.tflite"
        if candidate.exists():
            baseline_path = candidate

    print(f"Loading dataset: {args.data}")
    records = read_jsonl(args.data)

    print("Preprocessing and extracting features...")
    dataset = build_dataset(records)
    x = dataset.features
    y_true = dataset.target.flatten()

    print(f"Evaluating quantized model: {args.model}")
    quant_eval = evaluate_tflite_model(args.model, x, y_true)

    baseline_eval = None
    if baseline_path and baseline_path.exists():
        print(f"Evaluating baseline float32 model: {baseline_path}")
        baseline_eval = evaluate_tflite_model(baseline_path, x, y_true)

    total_samples = len(x)
    errors = quant_eval["errors"]
    y_pred = quant_eval["y_pred"]

    # Build worst predictions list
    worst_indices = np.argsort(errors)[::-1][:100]
    worst_predictions = []
    for rank, idx in enumerate(worst_indices, start=1):
        rec = records[idx]
        worst_predictions.append(
            {
                "rank": rank,
                "id": rec.get("id"),
                "app_name": rec.get("app_name"),
                "title": rec.get("title"),
                "body": rec.get("body"),
                "expected": float(y_true[idx]),
                "predicted": float(y_pred[idx]),
                "error": float(errors[idx]),
            }
        )

    # Write worst predictions details to JSON for manual review
    worst_json_path = args.out.parent / "worst_100_predictions.json"
    write_json(worst_json_path, worst_predictions)

    # Prepare markdown report
    report = []
    report.append("# Ghost AI Model Validation Report")
    report.append("")
    report.append(f"**Quantized Model Path:** `{args.model}`")
    if baseline_eval:
        report.append(f"**Baseline Model Path:** `{baseline_path}`")
    report.append(f"**Dataset Path:** `{args.data}`")
    report.append(f"**Total Samples:** {total_samples:,}")
    report.append("")

    report.append("## Tensor Contracts & Shape Signatures")
    report.append("")
    report.append("| Tensor | Type | Shape | Shape Signature |")
    report.append("| :--- | :--- | :--- | :--- |")
    report.append(
        f"| **Input Features** | `{quant_eval['input_dtype']}` | `{quant_eval['input_shape']}` | `{quant_eval['input_shape_sig']}` |"
    )
    report.append(
        f"| **Output Score** | `{quant_eval['output_dtype']}` | `{quant_eval['output_shape']}` | `{quant_eval['output_shape_sig']}` |"
    )
    report.append("")

    report.append("## Core Metrics")
    report.append("")
    if baseline_eval:
        report.append("| Metric | Float32 Baseline | Int8 Quantized | Delta / Status |")
        report.append("| :--- | :--- | :--- | :--- |")
        mae_diff = quant_eval["mae"] - baseline_eval["mae"]
        mae_pct = (mae_diff / baseline_eval["mae"] * 100.0) if baseline_eval["mae"] > 0 else 0.0
        report.append(
            f"| **MAE** | `{baseline_eval['mae']:.2f}` | `{quant_eval['mae']:.2f}` | `{mae_diff:+.2f}` ({mae_pct:+.1f}%) |"
        )
        report.append(
            f"| **RMSE** | `{baseline_eval['rmse']:.2f}` | `{quant_eval['rmse']:.2f}` | `{quant_eval['rmse'] - baseline_eval['rmse']:+.2f}` |"
        )
        report.append(
            f"| **R²** | `{baseline_eval['r2']:.4f}` | `{quant_eval['r2']:.4f}` | `{quant_eval['r2'] - baseline_eval['r2']:+.4f}` |"
        )
        report.append(
            f"| **Avg Inference Time** | `{baseline_eval['avg_latency_ms']:.3f} ms` | `{quant_eval['avg_latency_ms']:.3f} ms` | `{quant_eval['avg_latency_ms'] - baseline_eval['avg_latency_ms']:+.3f} ms` |"
        )
        report.append(
            f"| **95th percentile Latency** | `{baseline_eval['p95_latency_ms']:.3f} ms` | `{quant_eval['p95_latency_ms']:.3f} ms` | `{quant_eval['p95_latency_ms'] - baseline_eval['p95_latency_ms']:+.3f} ms` |"
        )
        report.append(
            f"| **Wrong predictions (>30 pts)** | `{baseline_eval['wrong_count']:,}` ({baseline_eval['wrong_percentage']:.2f}%) | `{quant_eval['wrong_count']:,}` ({quant_eval['wrong_percentage']:.2f}%) | `{quant_eval['wrong_count'] - baseline_eval['wrong_count']:+d}` |"
        )

        size_float = baseline_eval["size_bytes"]
        size_quant = quant_eval["size_bytes"]
        reduction_pct = (1.0 - (size_quant / size_float)) * 100.0
        report.append("")
        report.append("## Asset Size Benchmark")
        report.append("")
        report.append("| Model Format | Size (bytes) | Size (KB) | Reduction |")
        report.append("| :--- | :--- | :--- | :--- |")
        report.append(f"| Float32 Baseline | `{size_float:,}` | `{size_float/1024:.1f} KB` | Baseline |")
        report.append(f"| Int8 Quantized | `{size_quant:,}` | `{size_quant/1024:.1f} KB` | **{reduction_pct:.1f}% reduction** |")
    else:
        report.append("| Metric | Result | Description |")
        report.append("| :--- | :--- | :--- |")
        report.append(f"| **MAE** | `{quant_eval['mae']:.2f}` | Mean Absolute Error |")
        report.append(f"| **RMSE** | `{quant_eval['rmse']:.2f}` | Root Mean Squared Error |")
        report.append(f"| **R²** | `{quant_eval['r2']:.4f}` | Coefficient of Determination |")
        report.append(
            f"| **Avg Inference Time** | `{quant_eval['avg_latency_ms']:.3f} ms` | Average time per single inference |"
        )
        report.append(
            f"| **95th percentile Latency** | `{quant_eval['p95_latency_ms']:.3f} ms` | 95% of inferences are faster than this |"
        )
        report.append(
            f"| **Wrong predictions (>30 pts)** | `{quant_eval['wrong_count']:,} ({quant_eval['wrong_percentage']:.2f}%)` | Count & % of predictions with error > 30 |"
        )
        report.append(
            f"| **Model Size** | `{quant_eval['size_bytes']:,} bytes ({quant_eval['size_bytes']/1024:.1f} KB)` | Binary size on disk |"
        )

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
    report.append(
        f"Detailed worst 100 predictions written to: [`worst_100_predictions.json`](file://{worst_json_path})"
    )

    # Save Markdown report
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(report), encoding="utf-8")
    print(f"\nReport written to: {args.out}")

    print("\nCore Results Summary:")
    print(f"MAE: {quant_eval['mae']:.2f}")
    print(f"RMSE: {quant_eval['rmse']:.2f}")
    print(f"R2: {quant_eval['r2']:.4f}")
    print(f"Avg Inference: {quant_eval['avg_latency_ms']:.3f} ms")
    print(
        f"Wrong predictions (>30 pts): {quant_eval['wrong_count']:,} ({quant_eval['wrong_percentage']:.2f}%)"
    )
    if baseline_eval:
        reduction_pct = (1.0 - (quant_eval["size_bytes"] / baseline_eval["size_bytes"])) * 100.0
        print(f"Size Reduction vs Float32: {reduction_pct:.2f}%")


if __name__ == "__main__":
    main()
