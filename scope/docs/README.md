# Scope — Documentation Suite

> **Never Miss What Matters**

Version: **1.0**
Status: **Production Documentation**
Platform: **Android (Flutter)**

---

# Documentation Overview

This documentation suite provides a complete technical reference for **Scope**, an AI-powered Notification Attention Manager.

The documentation is organized from high-level product concepts to low-level engineering details. Readers unfamiliar with the project should begin with the **System Overview** before proceeding through the remaining documents.

The suite is intended for:

* Hackathon judges
* Software engineers
* Open-source contributors
* Future maintainers
* Technical reviewers

---

# Documentation Structure

```
docs/
│
├── 00_system_overview.md
│
├── 01_technical_design_document.md
│
├── 02_system_architecture.md
│
├── 03_notification_pipeline.md
│
├── 04_ghost_ai.md
│
├── 05_database.md
│
├── 06_review_queue.md
│
├── 07_ui_ux.md
│
├── 08_smart_actions.md
│
├── 09_ghost_ai_playground.md
│
├── 10_insights.md
│
├── 11_privacy_and_security.md
│
├── 12_testing_strategy.md
│
├── 13_roadmap.md
│
├── diagrams/
│
└── archive/
```

---

# Reading Order

The documentation should be read in the following sequence.

```
README

↓

00 System Overview

↓

Technical Design Document

↓

System Architecture

↓

Notification Pipeline

↓

Ghost AI

↓

Database

↓

Review Queue

↓

UI / UX

↓

Smart Actions

↓

Ghost AI Playground

↓

Insights

↓

Privacy & Security

↓

Testing Strategy

↓

Roadmap
```

---

# Document Descriptions

## README

Public-facing introduction to Scope.

Contains:

* Overview
* Features
* Screenshots
* Installation
* Demo
* Technology stack

---

## 00 — System Overview

The canonical reference document.

Introduces:

* Product vision
* Design philosophy
* Core principles
* High-level architecture
* Notification lifecycle
* Technology stack
* Terminology

Every other document references this file instead of redefining concepts.

---

## 01 — Technical Design Document

Complete engineering specification.

Includes:

* Functional requirements
* Non-functional requirements
* Constraints
* Design decisions
* Quality attributes
* System behavior
* Future extensibility

---

## 02 — System Architecture

Complete architectural reference.

Contains:

* Layered architecture
* Component diagrams
* Module interactions
* Sequence diagrams
* Data flow
* Native integration

---

## 03 — Notification Pipeline

Documents the entire notification lifecycle.

Topics include:

* Android capture
* Native bridge
* Ghost AI analysis
* Persistence
* Review Queue
* Presentation layer

---

## 04 — Ghost AI

Technical reference for the on-device intelligence engine.

Explains:

* Feature extraction
* Metadata analysis
* Rule engine
* TFLite classifier
* Score fusion
* Policy engine
* Explanation generation
* Priority resolution

---

## 05 — Database

Persistence architecture.

Documents:

* Drift schema
* Entity relationships
* Storage lifecycle
* Migrations
* Repository layer

---

## 06 — Review Queue

State management reference.

Explains:

* Review states
* Queue lifecycle
* Filters
* Focus Areas
* Archiving
* Snoozing
* Rescoring

---

## 07 — UI / UX

Documents the product experience.

Includes:

* Design philosophy
* Navigation
* Motion
* Accessibility
* Interaction patterns
* Information hierarchy

---

## 08 — Smart Actions

Documents contextual actions.

Includes:

* Decision logic
* Action mapping
* Calendar reminders
* Notification shortcuts
* User confirmation flow

---

## 09 — Ghost AI Playground

Developer-only diagnostics interface.

Provides visibility into:

* Classification behavior
* Extracted features
* Policy decisions
* Priority reasoning
* Simulator Mode
* Explainability

This is **not** a reinforcement learning or model-training system.

---

## 10 — Insights

Analytics reference.

Documents:

* Priority distribution
* Notification trends
* Focus Area statistics
* Analysis summaries
* Productivity metrics

---

## 11 — Privacy & Security

Privacy architecture.

Explains:

* On-device processing
* Offline operation
* Local persistence
* Security boundaries
* User data ownership

---

## 12 — Testing Strategy

Quality assurance reference.

Documents:

* Unit testing
* Widget testing
* Integration testing
* Regression testing
* Performance validation

---

## 13 — Roadmap

Future direction.

Organized into:

* Current Release
* Near-term Improvements
* Long-term Vision

---

# Diagram Inventory

The documentation uses a consistent set of architecture diagrams.

## Architecture

* Overall System Architecture

## Notification Flow

* Notification Lifecycle
* Native Integration

## Ghost AI

* Ghost AI Pipeline
* Policy Resolution

## State

* Review Queue State Machine

## Persistence

* Database ER Diagram

## Presentation

* Navigation Flow
* Flutter Layer Architecture

## Smart Actions

* Decision Flow

All diagrams share the same visual style and terminology.

---

# Design Principles

The documentation follows these principles:

* Single source of truth
* Diagram-first explanations
* Minimal duplication
* Consistent terminology
* Clear engineering rationale
* Production-quality writing
* Privacy-first design
* Explainable AI

---

# Terminology Policy

Terms defined in **00_system_overview.md** are considered canonical.

Other documents reference those definitions instead of redefining them.

This ensures consistency across the entire documentation suite.

---

# Historical Documents

Development-phase documents remain available under:

```
docs/archive/
```

These provide implementation history but are no longer considered the primary engineering reference.

The current documentation reflects the latest architecture and supersedes historical phase notes where differences exist.

---

# Maintenance Guidelines

When introducing a new feature:

1. Update System Overview.
2. Update TDD if architecture changes.
3. Update System Architecture if modules change.
4. Update Ghost AI if intelligence changes.
5. Update UI/UX if interaction changes.
6. Update Testing Strategy.
7. Update Roadmap if future plans are affected.

Avoid duplicating explanations across documents.

Instead, extend the appropriate canonical document and reference it elsewhere.

---

# Documentation Philosophy

Scope is designed as a long-term software product rather than a hackathon prototype.

Its documentation follows the same philosophy.

Every document should answer three questions:

1. **What does this component do?**
2. **Why was it designed this way?**
3. **How does it interact with the rest of the system?**

By keeping each document focused, consistent, and diagram-driven, the documentation remains approachable for new contributors while providing sufficient technical depth for experienced engineers and hackathon judges.
