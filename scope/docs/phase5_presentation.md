# Phase 5: Presentation Layer — Documentation

## Overview

Phase 5 transforms AttentionOS from a functional notification feed into a **productivity workspace**. Notifications become actions, deadlines, and decisions — not a scrollable inbox.

The AI pipeline (Ghost AI) remains invisible infrastructure. The product answers **"What should I do next?"** instead of **"What notification arrived?"**

## Architecture (Preserved)

```
NotificationController
        ↓
   MainShell (bottom nav)
   ├── HomeScreen
   ├── FocusScreen
   ├── SearchScreen
   ├── InsightsScreen
   └── SettingsScreen
```

### Key Files Added

| Path | Purpose |
|---|---|
| `lib/theme/app_theme.dart` | Material 3 Scandinavian theme, 16dp cards |
| `lib/core/state/notification_controller.dart` | Shared notification + action state |
| `lib/core/utils/focus_area_mapper.dart` | Maps notifications → focus areas |
| `lib/core/utils/smart_actions.dart` | Contextual action generation |
| `lib/core/utils/greeting_util.dart` | Time-of-day greeting |
| `lib/screens/main_shell.dart` | Bottom navigation shell |
| `lib/screens/home_screen.dart` | Dashboard (not a notification list) |
| `lib/screens/focus_screen.dart` | One-at-a-time review sessions |
| `lib/screens/focus_complete_screen.dart` | Session completion summary |
| `lib/screens/notification_detail_screen.dart` | Action detail (no auto app launch) |
| `lib/screens/search_screen.dart` | Full-text search |
| `lib/screens/insights_screen.dart` | Priority + focus analytics |
| `lib/screens/settings_screen.dart` | Privacy, dev tools, diagnostics |
| `lib/widgets/*` | Reusable UI components |

### Reusable Widgets

- `DailyBriefCard` — Today's summary
- `ActionQueueWidget` / `SummaryCard` — Needs Action, Important, Archived
- `FocusAreaCard` — Badge counts per life area
- `ReviewCard` — Single notification in Focus
- `AIReasonWidget` — "Why this matters"
- `SmartActionChip` — Contextual actions
- `ProgressWidget` — Daily completion bar
- `NotificationInsightCard` — Search result card
- `ScopeCard` — Base 16dp-radius card
- `EmptyState` — Positive empty states

## Home Screen

Does **not** begin with a notification list.

Shows:
1. Time-based greeting
2. Today's Brief (AI review summary)
3. Action queues (Needs Action / Important / Archived counts)
4. Progress (completed today)
5. Focus Areas (badge counts only)
6. Start Focus Session CTA

## Focus Session

Signature feature — one notification at a time with smart actions, archive, and next.

## Notification Detail

Never auto-opens the originating app. Shows original content, AI summary, extracted info, and suggested actions. App launch is explicit only.

## Navigation

Bottom nav: **Home · Focus · Search · Insights · Settings**

## How to Test

```bash
flutter run
```

1. Settings → **Load Test Data**
2. Home dashboard populates with focus areas and brief
3. Focus → **Begin Review Session**
4. Search, Insights, Settings verify secondary flows

## Design Principles

- No traditional notification shade / inbox
- Calm, minimal, professional (Linear / Notion aesthetic)
- Color only for urgency
- No glassmorphism, neon, or AI robot imagery
