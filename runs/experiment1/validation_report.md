# Ghost AI Model Validation Report

**Model Path:** `/app/scope/runs/experiment1/export/ghost_ai_quantized.tflite`
**Dataset Path:** `/app/scope/attentionos-dataset/output/notifications_100000_seed42.jsonl`
**Total Samples:** 10,000

## Core Metrics

| Metric | Result | Description |
| :--- | :--- | :--- |
| **MAE** | `18338.92` | Mean Absolute Error |
| **RMSE** | `18338.95` | Root Mean Squared Error |
| **R²** | `-363110.41` | Coefficient of Determination |
| **Avg Inference Time** | `0.007 ms` | Average time per single inference |
| **95th percentile Latency** | `0.006 ms` | 95% of inferences are faster than this |
| **Wrong predictions (>30 pts)** | `10,000 (100.00%)` | Count & % of predictions with error > 30 |

## Worst 100 Predictions (Top 10)

| Rank | App Name | Title | Body | Expected | Predicted | Absolute Error |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | Zomato | Coupon unlocked | Save ₹199 on FreshMart orders today. Cod... | 0.0 | 18406.8 | 18406.8 |
| 2 | Myntra | Offer for you | SAVE67 gives extra 10% off until 9:24 PM... | 0.0 | 18406.8 | 18406.8 |
| 3 | Myntra | Offer for you | Save ₹149 on UrbanCart orders today. Cod... | 0.0 | 18406.8 | 18406.8 |
| 4 | Swiggy | Coupon unlocked | Save ₹99 on Green Basket orders today. C... | 0.0 | 18406.8 | 18406.8 |
| 5 | Zomato | Coupon unlocked | SAVE52 gives extra 20% off until 6:11 PM... | 0.0 | 18406.8 | 18406.8 |
| 6 | Myntra | Offer for you | SAVE73 gives extra 15% off until 1:59 AM... | 0.0 | 18406.8 | 18406.8 |
| 7 | Myntra | Coupon unlocked | Save ₹199 on UrbanCart orders today. Cod... | 0.0 | 18406.8 | 18406.8 |
| 8 | Netflix | Continue watching | City Lights is now streaming. Pick up fr... | 0.0 | 18406.8 | 18406.8 |
| 9 | Myntra | Offer for you | Save ₹99 on NovaPay orders today. Code S... | 0.0 | 18406.8 | 18406.8 |
| 10 | Zomato | Offer for you | SAVE43 gives extra 40% off until 5:37 AM... | 0.0 | 18406.8 | 18406.8 |

Detailed worst 100 predictions written to: [`worst_100_predictions.json`](file:///app/scope/runs/experiment1/worst_100_predictions.json)