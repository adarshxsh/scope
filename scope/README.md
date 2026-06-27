# Scope (AttentionOS)

An AI-powered Attention Operating System for Android. Scope analyzes notifications on-device and helps you review, prioritize, and act on what matters — without endless scrolling.

## What it does

- Captures Android notifications via `NotificationListenerService`
- Analyzes them on-device with **Ghost AI** (rules + LiteRT classifier)
- Presents a **productivity workspace** — not a notification inbox

## Quick start

```bash
flutter pub get
flutter run
```

1. Grant notification access in **Settings → Notification access → AttentionOS**
2. Or use **Settings → Load Test Data** in the app to demo with sample notifications
3. Start a **Focus Session** from the home dashboard

## Architecture

```
Android OS → NotificationCollectorService → MethodChannel → Flutter
                                                              ↓
                                                    GhostAnalysisEngine
                                                              ↓
                                                   NotificationController
                                                              ↓
                                                        MainShell UI
```

## Docs

- [Progress tracker](docs/PROGRESS.md)
- [Phase 1: Foundation](docs/phase1_foundation.md)
- [Phase 2: Ghost AI](docs/phase2_ghost_ai.md)
- [Phase 5: Presentation](docs/phase5_presentation.md)
- [Phase 6: Premium UX](docs/phase6_premium_ux.md)

## Tests

```bash
flutter test
```
