import 'package:flutter/material.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/theme/motion.dart';

/// Contextual action chip with color, icon, and animated selection state.
class SmartActionChip extends StatelessWidget {
  final SmartAction action;
  final VoidCallback? onPressed;
  final bool selected;

  const SmartActionChip({
    super.key,
    required this.action,
    this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = action.color ?? theme.colorScheme.primary;

    return Semantics(
      button: true,
      label: action.label,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.enter,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.16)
              : accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : accent.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    action.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
