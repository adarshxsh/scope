import 'package:flutter/material.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Focus area tile — icon, title, count, description.
class FocusAreaCard extends StatelessWidget {
  final FocusArea area;
  final int count;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  const FocusAreaCard({
    super.key,
    required this.area,
    required this.count,
    required this.description,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '${area.label}, $description',
      child: ScopeSurface(
        onTap: onTap,
        elevated: !selected,
        borderColor: selected
            ? theme.colorScheme.onSurface.withValues(alpha: 0.25)
            : null,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ScopeIconBox(icon: area.icon, size: ScopeIconBoxSize.sm),
                const Spacer(),
                Text(
                  '$count',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: count > 0
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Spacer(),
            Text(area.label, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
