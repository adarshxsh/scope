# Phase 2: Ghost AI (Analysis Engine) — Documentation

## Overview

Phase 2 implements the core intelligence engine of AttentionOS, named **Ghost AI**. The engine processes raw captured notifications through a hybrid intelligence pipeline, combining deterministic features, data-driven rules, and on-device machine learning classification to resolve business priority levels with absolute explainability.

## Hybrid Intelligence Pipeline Architecture

The pipeline processes each notification sequentially using a single-responsibility architecture, making it highly modular and testable.

```
          Raw Notification Input
                    ↓
              Normalization (Trim, lower-case, collapse whitespace)
                    ↓
             FeatureExtractor (Parses OTPs, Currency, Deadlines, Links, etc.)
                    ↓
             MetadataAnalyzer (Matches package names to category mappings)
                    ↓
            ┌───────┴───────┐
            ▼               ▼
       RuleEngine     LiteRtClassifier (WordPiece Tokenizer + Category logits)
     (JSON compiled)        │
            └───────┬───────┘
                    ▼
               ScoreFusion (Applies confidence scoring or critical bypass)
                    ↓
              PolicyEngine (Determines final Priority: critical/high/med/low)
                    ↓
          ExplanationGenerator (Generates natural language trace of decision)
                    ↓
           Analyzed Notification Model Output (stored and rendered)
```

## Core Components

| Component | Responsibility | Details |
|---|---|---|
| `AppNotification` | Data Model | Extended with analysis parameters (`priority`, `latencyMs`, `explanation`, `extractedFeatures`, versions). |
| `FeatureExtractor` | Feature Extraction | Normalizes text and runs regexes to parse OTP codes (4-8 digits), transaction amounts (e.g. `Rs. 15,000` → `15000.0`), deadlines, URLs, emails, and phone numbers. |
| `MetadataAnalyzer` | Metadata Heuristics | Maps package names to semantic category tags (e.g., `com.whatsapp` → `msg`, `com.hdfc` → `finance`) and filters system-ongoing states. |
| `RuleEngine` | Data-driven Rules | Loads, compiles, and parses `assets/rules.json` on startup. Performs fast in-memory keyword, package, and title matches. |
| `WordPieceTokenizer` | Subword Encoding | Pure Dart implementation of the WordPiece tokenizer mapping words/subwords (prefixed with `##`) to vocabulary index positions. |
| `LiteRtClassifier` | ML Classification | Wraps `tflite_flutter` to execute on-device inference for semantic category probabilities. Integrates graceful fallback heuristics on dynamic library loading errors. |
| `ScoreFusion` | Fusion Stage | Resolves conflict scores. Triggers an immediate bypass path for critical security alerts (UPI transaction debits, OTPs). |
| `PolicyEngine` | Decision Logic | Maps fused categories and matched features to priority tiers (`critical` / `high` / `medium` / `low`). |
| `ExplanationGenerator` | Explainability | Generates a natural-language bulleted list tracing the pipeline execution logic (visible in diagnostics and logs). |
| `GhostAnalysisEngine` | Coordinator Hub | Orchestrates the pipeline stages, tracks processing latency, and decorates the final notification model. |

## Visual Priority Design

The notification feed UI highlights priority visually to guide user attention:
* **CRITICAL**: Red card border, red avatar badge with a security shield icon (`Icons.gpp_bad`).
* **HIGH**: Orange card border, orange avatar badge with an alert indicator (`Icons.warning_amber_rounded`).
* **MEDIUM**: Blue card border, blue/grey notification icon.
* **LOW**: Grey border, dimmed title/content opacity (65%), removing screen clutter.

## Diagnostics Dashboard

We implemented an interactive diagnostics panel accessed via the analytics icon button in the App Bar.
1. **Templates Dropdown**: Quick-apply templates (WhatsApp Mom chat, HDFC Bank transaction, GSoC email, Apollo medical appointment).
2. **Custom Input Forms**: Let developers modify Title, Body, Package, and Ongoing states.
3. **Execution Trace Panels**: Displays extracted features, matched rules, model scores, latency (ms), and natural-language pipeline explanations.

## How to Test

### Run All Unit and Widget Tests
```bash
flutter test
```
This executes all 72 test suites covering:
* Regex feature parsing (currency, OTPs, urls, emails, phones)
* WordPiece tokenization logic (padding, subwords, special tokens)
* Rule engine JSON compiler and matches
* Classifier fallbacks and graceful degradation
* Coordinator pipelines
* Diagnostic dashboard widget rendering
* Notification feed priority visualization
