import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_elevation.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/app_theme.dart';
import 'package:scope/theme/motion.dart';

import 'package:scope/widgets/motion/motion_surface.dart';

enum ScopeSurfaceVariant { solid, glass, glassDark }

/// Unified surface primitive for Scope's dark design system.
///
/// Variants:
/// - [solid]     — the standard elevated dark card (AppColors.surface).
/// - [glass]     — subtle frosted panel, lighter tint (used on focus/immersive).
/// - [glassDark] — deeper frosted layer for the dark focus session background.
class ScopeSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final VoidCallback? onTap;
  final ScopeSurfaceVariant variant;
  final bool elevated;
  final bool animatePress;
  final bool glow;

  const ScopeSurface({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.onTap,
    this.variant = ScopeSurfaceVariant.solid,
    this.elevated = true,
    this.animatePress = true,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusLg);
    final pad = padding ?? const EdgeInsets.all(AppSpacing.lg);

    Widget surface = switch (variant) {
      ScopeSurfaceVariant.glass || ScopeSurfaceVariant.glassDark =>
        _GlassLayer(
          padding: pad,
          radius: radius,
          dark: variant == ScopeSurfaceVariant.glassDark,
          borderColor: borderColor,
          glow: glow,
          onTap: onTap,
          child: child,
        ),
      ScopeSurfaceVariant.solid => _SolidLayer(
          padding: pad,
          radius: radius,
          borderColor: borderColor,
          elevated: elevated,
          onTap: onTap != null && animatePress ? null : onTap,
          child: child,
        ),
    };

    if (onTap != null && animatePress && variant == ScopeSurfaceVariant.solid) {
      return MotionSurface(
        onTap: onTap!, 
        borderRadius: radius,
        child: surface,
      );
    }

    return surface;
  }
}

// ── Solid dark card ──────────────────────────────────────────────────────────

class _SolidLayer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;
  final Color? borderColor;
  final bool elevated;
  final VoidCallback? onTap;

  const _SolidLayer({
    required this.child,
    required this.padding,
    required this.radius,
    this.borderColor,
    required this.elevated,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: AppColors.surface,
      borderRadius: radius,
      border: Border.all(
        color: borderColor ?? AppColors.border,
        width: 1,
      ),
      boxShadow: elevated ? AppElevation.card : null,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: AppColors.onSurface.withValues(alpha: 0.04),
        highlightColor: AppColors.onSurface.withValues(alpha: 0.02),
        child: Ink(
          decoration: decoration,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ── Glass / frosted layer ────────────────────────────────────────────────────

class _GlassLayer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;
  final bool dark;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool glow;

  const _GlassLayer({
    required this.child,
    required this.padding,
    required this.radius,
    required this.dark,
    this.borderColor,
    this.onTap,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    // Tint the opaque background glass slightly with the border color
    final baseColor = dark ? AppColors.scaffold : AppColors.surface;
    
    Color fill = baseColor.withValues(alpha: 0.85); // Very opaque base
    if (borderColor != null) {
      fill = Color.alphaBlend(
        borderColor!.withValues(alpha: 0.15),
        fill,
      );
    }
    final border = borderColor ??
        (dark
            ? AppColors.onSurface.withValues(alpha: 0.08)
            : AppColors.border);

    final surface = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // Increased blur for premium glass feel
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(color: border, width: 1),
            boxShadow: glow && borderColor != null ? [
              BoxShadow(
                color: borderColor!.withValues(alpha: 0.2),
                blurRadius: 32,
                spreadRadius: -8,
              )
            ] : null,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (onTap == null) return surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: AppColors.onSurface.withValues(alpha: 0.04),
        child: surface,
      ),
    );
  }
}

// Removed _PressScale in favor of MotionSurface in lib/widgets/motion/motion_surface.dart

/// Backward-compatible alias — prefer [ScopeSurface] directly.
class ScopeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool glass;
  final bool elevated;

  const ScopeCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.onTap,
    this.glass = false,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    return ScopeSurface(
      padding: padding,
      borderColor: borderColor,
      onTap: onTap,
      elevated: elevated,
      variant: glass ? ScopeSurfaceVariant.glass : ScopeSurfaceVariant.solid,
      child: child,
    );
  }
}
