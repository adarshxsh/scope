import 'package:flutter/material.dart';

/// Elevation and shadow tokens for dark surfaces.
/// Shadows on dark use a deeper black at low opacity — subtle depth, no glow.
abstract final class AppElevation {
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get lifted => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get selected => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}
