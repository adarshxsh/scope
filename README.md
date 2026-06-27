# SCOPE (Smart Contextual Opportunity & Priority Engine)

**SCOPE** is an AI-powered attention management system for Android. It acts as a premium "AttentionOS" layer, identifying and resurfacing critical government, financial, and educational alerts that are often buried under everyday notification noise.

## 🚀 Features

- **Ghost AI Engine**: A hybrid local machine learning pipeline featuring a deterministic rule engine, WordPiece NLP tokenization, and a quantized TensorFlow Lite (LiteRT) Multi-Layer Perceptron (MLP) model. Ghost AI scores and classifies incoming notifications instantly without relying on the cloud.
- **Review Queue System**: A state-machine-driven queue that actively syncs with the Android notification panel, allowing you to seamlessly Snooze, Archive, and Review alerts.
- **Immersive Focus Mode**: A beautiful, distraction-free vertical swipe interface (similar to Instagram Reels) to focus strictly on important tasks one by one.
- **Premium UI/UX**: Built with a custom glassmorphic motion design system, featuring physics-based spring animations, adaptive priority cards (glow effects for critical alerts), and interactive Daily Timeline insights.
- **Privacy-First**: A persistent, fully local SQLite database (powered by Drift) securely manages all notification ingestion, telemetry, and expiry natively on-device.

## 🛠 Tech Stack

- **Frontend**: Flutter & Dart
- **Backend / Storage**: SQLite via Drift
- **Machine Learning**: TensorFlow Lite, Python (for training pipeline)
- **Native Android**: Kotlin (NotificationListenerService)
