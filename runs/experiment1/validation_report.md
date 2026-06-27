# Ghost AI Model Validation Report

**Model Path:** `runs/experiment1/export/ghost_ai.tflite`
**Dataset Path:** `attentionos-dataset/output/notifications_100000_seed42.jsonl`
**Total Samples:** 100,000

## Core Metrics

| Metric | Result | Description |
| :--- | :--- | :--- |
| **MAE** | `2.18` | Mean Absolute Error |
| **RMSE** | `3.14` | Root Mean Squared Error |
| **R²** | `0.99` | Coefficient of Determination |
| **Avg Inference Time** | `0.002 ms` | Average time per single inference |
| **95th percentile Latency** | `0.002 ms` | 95% of inferences are faster than this |
| **Wrong predictions (>30 pts)** | `92 (0.09%)` | Count & % of predictions with error > 30 |

## Worst 100 Predictions (Top 10)

| Rank | App Name | Title | Body | Expected | Predicted | Absolute Error |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | YouTube | Continue watching | New episode of The Final Over is availab... | 0.0 | 47.5 | 47.5 |
| 2 | YouTube | New for you | New episode of The Final Over is availab... | 0.0 | 47.2 | 47.2 |
| 3 | YouTube | New for you | New episode of Startup Stories is availa... | 0.0 | 43.9 | 43.9 |
| 4 | Jira | Reset code sent | Password change started from Kochi. Secu... | 100.0 | 56.1 | 43.9 |
| 5 | Gmail | Invoice approval | Invoice approval — can you confirm this ... | 35.0 | 78.4 | 43.4 |
| 6 | Spotify | New for you | New episode of City Lights is available ... | 0.0 | 42.6 | 42.6 |
| 7 | Outlook | Interview feedback | Interview feedback — please check the la... | 35.0 | 77.2 | 42.2 |
| 8 | Netflix | New for you | New episode of Weekend Kitchen is availa... | 0.0 | 42.2 | 42.2 |
| 9 | Gmail | Interview feedback | Interview feedback — sharing the revised... | 40.0 | 81.7 | 41.7 |
| 10 | Outlook | Interview feedback | Riya sent an email with a spreadsheet. | 35.0 | 75.9 | 40.9 |

Detailed worst 100 predictions written to: [`worst_100_predictions.json`](file://runs/experiment1/worst_100_predictions.json)