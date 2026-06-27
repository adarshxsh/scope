import 'package:flutter/material.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/app_theme.dart';
import 'package:scope/theme/motion.dart';

import 'package:scope/widgets/motion/motion_surface.dart';

enum ScopeChipTone { neutral, accent }

/// Base chip primitive — used by [SmartActionChip].
class ScopeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final bool inverted;
  final Color? accent;
  final ScopeChipTone tone;

  const ScopeChip({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.selected = false,
    this.inverted = false,
    this.accent,
    this.tone = ScopeChipTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = accent ?? theme.colorScheme.onSurface;
    final useAccent = tone == ScopeChipTone.accent;

    final fill = inverted
        ? Colors.white.withValues(alpha: selected ? 0.16 : 0.08)
        : (useAccent ? base.withValues(alpha: selected ? 0.12 : 0.06) : theme.colorScheme.onSurface.withValues(alpha: selected ? 0.08 : 0.04));

    final border = inverted
        ? Colors.white.withValues(alpha: selected ? 0.35 : 0.14)
        : (useAccent ? base.withValues(alpha: selected ? 0.4 : 0.15) : theme.colorScheme.onSurface.withValues(alpha: selected ? 0.2 : 0.08));

    final labelColor = inverted
        ? Colors.white.withValues(alpha: selected ? 1 : 0.85)
        : theme.colorScheme.onSurface.withValues(alpha: selected ? 0.95 : 0.78);

    final iconColor = inverted
        ? Colors.white.withValues(alpha: 0.9)
        : (useAccent ? base : theme.colorScheme.onSurface.withValues(alpha: 0.55));

    return Semantics(
      button: true,
      label: label,
      child: MotionSurface(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.enter,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: iconColor),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: labelColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
