from __future__ import annotations

import argparse
import json
from itertools import tee
from pathlib import Path

from export.csv import write_csv
from export.jsonl import write_jsonl
from generator import NotificationDatasetGenerator
from validator.statistics import summarize


SUPPORTED_SIZES = {10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate AttentionOS synthetic Android notification datasets.")
    parser.add_argument("--count", type=int, default=100_000, help="Number of notifications to generate.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for reproducible output.")
    parser.add_argument("--format", choices=("jsonl", "csv"), default="jsonl", help="Export format.")
    parser.add_argument("--output", type=Path, default=None, help="Output file path.")
    parser.add_argument("--ollama", action="store_true", help="Optionally call local Ollama for a small share of text variants.")
    parser.add_argument("--ollama-model", default="gemma3:9b", help="Local Ollama model name.")
    parser.add_argument("--stats", action="store_true", help="Write summary statistics next to the dataset.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.count <= 0:
        raise SystemExit("--count must be positive")
    if args.count not in SUPPORTED_SIZES:
        print(f"Note: {args.count} is supported. Standard presets are {sorted(SUPPORTED_SIZES)}.")

    output = args.output
    if output is None:
        output = Path("output") / f"notifications_{args.count}_{args.seed}.{args.format}"

    generator = NotificationDatasetGenerator(
        seed=args.seed,
        use_ollama=args.ollama,
        ollama_model=args.ollama_model,
    )
    records = generator.generate(args.count)

    if args.stats:
        records, stats_records = tee(records)
        stats = summarize(stats_records)
        stats_path = output.with_suffix(output.suffix + ".stats.json")
        stats_path.parent.mkdir(parents=True, exist_ok=True)
        stats_path.write_text(json.dumps(stats, indent=2, ensure_ascii=False), encoding="utf-8")

    if args.format == "jsonl":
        written = write_jsonl(output, records)
    else:
        written = write_csv(output, records)

    print(f"Wrote {written} notifications to {output}")


if __name__ == "__main__":
    main()
