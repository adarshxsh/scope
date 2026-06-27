import 'package:flutter/material.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Action queue summary tile — count is the primary signal.
class SummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final VoidCallback? onTap;

  const SummaryCard({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ScopeSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ScopeIconBox(icon: icon, size: ScopeIconBoxSize.md),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$count',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: count > 0
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
