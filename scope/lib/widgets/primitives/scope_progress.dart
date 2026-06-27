import 'package:flutter/material.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/widgets/motion/animated_count_text.dart';

enum ScopeProgressStyle { standard, compact }

/// Unified progress indicator — dashboard and focus session.
class ScopeProgress extends StatelessWidget {
  final int completed;
  final int total;
  final String label;
  final ScopeProgressStyle style;
  final bool inverted;

  const ScopeProgress({
    super.key,
    required this.completed,
    required this.total,
    this.label = "Today's Progress",
    this.style = ScopeProgressStyle.standard,
    this.inverted = false,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final theme = Theme.of(context);
    final compact = style == ScopeProgressStyle.compact;

    final labelStyle = inverted
        ? theme.textTheme.bodySmall?.copyWith(color: Colors.white54)
        : theme.textTheme.titleSmall;
    final metaStyle = inverted
        ? theme.textTheme.bodySmall?.copyWith(color: Colors.white38)
        : theme.textTheme.bodySmall;

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 2 : AppSpacing.xs),
      child: TweenAnimationBuilder<double>(
        key: ValueKey('$completed-$total-$inverted-$style'),
        tween: Tween(begin: 0, end: progress),
        duration: AppMotion.slow,
        curve: AppMotion.enter,
        builder: (context, value, _) {
          return LinearProgressIndicator(
            value: value,
            minHeight: compact ? 3 : AppSpacing.sm + 2,
            backgroundColor: inverted
                ? Colors.white.withValues(alpha: 0.10)
                : AppColors.onSurface.withValues(alpha: 0.08),
            color: inverted
                ? Colors.white.withValues(alpha: 0.65)
                : AppColors.portal,
          );
        },
      ),
    );

    if (compact) return bar;

    return Semantics(
      label: '$label, $completed of $total, $percent percent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: labelStyle),
              Row(
                children: [
                  AnimatedCountText(
                    value: percent,
                    suffix: '%',
                    style: metaStyle?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AnimatedCountText(value: completed, style: metaStyle),
                  Text(' / $total', style: metaStyle),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          bar,
        ],
      ),
    );
  }
}

@Deprecated('Use ScopeProgress')
typedef ProgressWidget = ScopeProgress;

@Deprecated('Use ScopeProgress with compact style')
class FocusSessionProgress extends StatelessWidget {
  final int current;
  final int total;

  const FocusSessionProgress({super.key, required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return ScopeProgress(
      completed: current,
      total: total,
      style: ScopeProgressStyle.compact,
      inverted: true,
    );
  }
}
