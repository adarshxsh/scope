import 'package:flutter/material.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/motion/animated_count_text.dart';

/// Unified label/value row for metrics, stats, and info panels.
class ScopeRow extends StatelessWidget {
  final String label;
  final String value;
  final bool animateValue;
  final String valueSuffix;

  const ScopeRow({
    super.key,
    required this.label,
    required this.value,
    this.animateValue = false,
    this.valueSuffix = '',
  });

  const ScopeRow.metric({
    super.key,
    required this.label,
    required int count,
    this.valueSuffix = '',
  })  : value = '$count',
        animateValue = true;

  const ScopeRow.info({
    super.key,
    required this.label,
    required this.value,
  })  : animateValue = false,
        valueSuffix = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: AppSpacing.md),
          if (animateValue)
            AnimatedCountText(
              value: int.tryParse(value) ?? 0,
              suffix: valueSuffix,
              style: theme.textTheme.titleSmall,
            )
          else
            Text('$value$valueSuffix', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// Key/value row with fixed label column — detail screens.
class ScopeInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const ScopeInfoRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Stat line with optional leading icon — briefs and summaries.
class ScopeStatLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const ScopeStatLine({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
