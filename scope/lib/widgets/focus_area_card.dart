import 'package:flutter/material.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/widgets/scope_card.dart';

/// Focus area tile with icon, count, and contextual description.
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
      label: '${area.label}, $description',
      child: AnimatedContainer(
        duration: AppMotion.standard,
        curve: AppMotion.enter,
        decoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.primary, width: 1.5),
              )
            : null,
        child: ScopeCard(
          onTap: onTap,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(area.icon, size: 18, color: theme.colorScheme.primary),
                  ),
                  const Spacer(),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(area.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
