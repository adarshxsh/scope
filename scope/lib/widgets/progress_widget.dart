import 'package:flutter/material.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/widgets/motion/animated_count_text.dart';

/// Animated daily progress with counting percentage.
class ProgressWidget extends StatelessWidget {
  final int completed;
  final int total;
  final String label;

  const ProgressWidget({
    super.key,
    required this.completed,
    required this.total,
    this.label = "Today's Progress",
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final theme = Theme.of(context);

    return Semantics(
      label: '$label, $completed of $total completed, $percent percent',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              Row(
                children: [
                  AnimatedCountText(
                    value: percent,
                    suffix: '%',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  AnimatedCountText(
                    value: completed,
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(' / $total completed', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('$completed-$total'),
              tween: Tween(begin: 0, end: progress),
              duration: AppMotion.slow,
              curve: AppMotion.enter,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: theme.colorScheme.primary,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
