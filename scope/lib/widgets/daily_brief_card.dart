import 'package:flutter/material.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Today's brief — premium home hero with dominant CTA.
class DailyBriefCard extends StatelessWidget {
  final int reviewedCount;
  final int actionCount;
  final int deadlineCount;
  final int financialUpdateCount;
  final int estimatedMinutes;
  final VoidCallback? onStartFocus;
  final VoidCallback? onTapCard;
  final bool canStartFocus;

  const DailyBriefCard({
    super.key,
    required this.reviewedCount,
    required this.actionCount,
    required this.deadlineCount,
    required this.financialUpdateCount,
    required this.estimatedMinutes,
    this.onStartFocus,
    this.onTapCard,
    this.canStartFocus = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeSaved = reviewedCount * 2; // Roughly 2 mins saved per blocked distraction

    return Hero(
      tag: 'daily_brief_hero',
      child: ScopeSurface(
        variant: ScopeSurfaceVariant.glass,
        onTap: onTapCard,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Time Saved',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.medium,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$timeSaved',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'min',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.critical.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.critical.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.priority_high, size: 14, color: AppColors.critical),
                    const SizedBox(width: 4),
                    Text(
                      '$actionCount actions',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.critical,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            reviewedCount == 0
                ? 'Ghost AI is monitoring your notifications. Relax, you are all caught up.'
                : 'Ghost AI safely intercepted $reviewedCount notifications today. You have $actionCount important items requiring your attention.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            height: 54, // Taller button for premium feel
            child: FilledButton(
              onPressed: canStartFocus ? onStartFocus : null,
              style: FilledButton.styleFrom(
                backgroundColor: canStartFocus ? AppColors.medium : AppColors.surfaceHigh,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: canStartFocus ? 8 : 0,
                shadowColor: AppColors.medium.withValues(alpha: 0.4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (canStartFocus)
                    const Icon(Icons.play_arrow_rounded, size: 24),
                  if (canStartFocus)
                    const SizedBox(width: 8),
                  Text(
                    canStartFocus ? 'Start Focus Session' : 'Nothing to review',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}
