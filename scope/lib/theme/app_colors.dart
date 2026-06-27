import 'package:flutter/material.dart';

/// Semantic color tokens — Scope dark design system.
///
/// Palette philosophy:
/// - Background layers use near-black with a barely-perceptible warm tint.
/// - Surfaces are elevated by lightness only — no glow, no blur noise.
/// - Accent is used ONLY for meaning (AI indicator, active state).
/// - Priority colors are desaturated slightly for dark-mode legibility.
abstract final class AppColors {
  // ── Background ──────────────────────────────────────────────────────────────
  /// Root scaffold background.
  static const scaffold = Color(0xFF0D0F14);

  /// Default card / surface fill.
  static const surface = Color(0xFF161A23);

  /// Slightly elevated surface (modals, popovers).
  static const surfaceHigh = Color(0xFF1E2330);

  // ── Borders ─────────────────────────────────────────────────────────────────
  /// Subtle divider / card border.
  static const border = Color(0xFF262A36);

  /// Stronger border for selected / focus states.
  static const borderStrong = Color(0xFF373D50);

  // ── Text ────────────────────────────────────────────────────────────────────
  /// Primary text on dark.
  static const onSurface = Color(0xFFEEF0F5);

  // ── Seed (Material color scheme generation) ──────────────────────────────────
  static const seed = Color(0xFF3A7BD5);

  // ── Semantic priority ────────────────────────────────────────────────────────
  /// Critical — vibrant coral, demands attention but remains premium.
  static const critical = Color(0xFFFF6B6B);

  /// High — warm amber/gold, elegant but noticeable.
  static const high = Color(0xFFFCA311);

  /// Medium — calm, deep sky blue.
  static const medium = Color(0xFF4D96FF);

  /// Low / neutral — muted slate, recedes into background.
  static const low = Color(0xFF6B7A99);

  // ── Premium Gradients ────────────────────────────────────────────────────────
  static const LinearGradient criticalGradient = LinearGradient(
    colors: [Color(0x33FF6B6B), Color(0x00FF6B6B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient highGradient = LinearGradient(
    colors: [Color(0x22FCA311), Color(0x00FCA311)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Action colours ───────────────────────────────────────────────────────────
  static const calendar = Color(0xFF3A7BD5);
  static const remind    = Color(0xFFE5923A);
  static const complete  = Color(0xFF3DAA6F);
  static const finance   = Color(0xFF8B5CF6);
  static const portal    = Color(0xFF2DB8A8);

  // ── Focus gradient (immersive session) ──────────────────────────────────────
  static const LinearGradient focusGradient = LinearGradient(
    colors: [Color(0xFF0A0C11), Color(0xFF111520), Color(0xFF0D1018)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Helpers ──────────────────────────────────────────────────────────────────
  static Color urgency(String? priority) => switch (priority) {
        'critical' => critical,
        'high'     => high,
        'medium'   => medium,
        _          => low,
      };

  static Color urgencyBg(String? priority) =>
      urgency(priority).withValues(alpha: 0.12);

  /// Muted text — 55 % of primary text.
  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

  /// Subtle text — 35 % of primary text.
  static Color subtle(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
}
