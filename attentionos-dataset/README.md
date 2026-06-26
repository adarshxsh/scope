# AttentionOS Synthetic Notification Dataset

This project generates realistic synthetic Android notifications for training on-device AttentionOS models.

It is designed for:

- category classification
- intent detection
- urgency detection
- action-required detection
- promotion detection
- duplicate detection
- recurring notification detection
- a deterministic `look_again` label

The default generator is fully offline, reproducible, and deterministic for a given seed. It does not call external APIs. An optional local Ollama mode can be enabled to vary a small portion of notification wording with `gemma3:9b`.

## Setup

```bash
cd attentionos-dataset
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Generate 100,000 Notifications

```bash
python generate.py --count 100000 --seed 42 --format jsonl --stats
```

Output:

```text
output/notifications_100000_42.jsonl
output/notifications_100000_42.jsonl.stats.json
```

## Optional Ollama Mode

Start Ollama locally with Gemma:

```bash
ollama run gemma3:9b
```

Then generate:

```bash
python generate.py --count 100000 --seed 42 --ollama
```

If Ollama is unavailable or times out, the generator falls back to offline templates.

## Supported Sizes

The CLI supports the requested presets without code changes:

- 10,000
- 50,000
- 100,000
- 250,000
- 500,000
- 1,000,000

Any positive count also works.

## Deterministic Priority and Look Again

Priority is not randomly assigned. `policy/scoring.py` computes:

- `priority_score`
- `priority`
- `urgency`
- `look_again_score`
- `look_again`
- `priority_reason`

Inputs include Android importance, category, notification type, OTP/security flags, money amounts, action requirement, intent, deadlines, recurrence, and promotional status.

## Schema

Each record includes notification text, package metadata, Android `NotificationListenerService`-style metadata, feature flags, extracted entities, policy labels, and model-training labels.
