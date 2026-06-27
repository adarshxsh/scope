import 'package:flutter/material.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Positive empty state used across screens.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    this.icon = Icons.check_circle_outline,
    required this.title,
    required this.message,
    this.action,
  });

  const EmptyState.caughtUp({super.key, this.action})
      : icon = Icons.check_circle_outline,
        title = "You're all caught up.",
        message = 'Everything important has been handled.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: '$title $message',
      child: SingleChildScrollView(
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ScopeSurface(
            variant: ScopeSurfaceVariant.glass,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.medium.withValues(alpha: 0.1),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.medium.withValues(alpha: 0.15),
                        blurRadius: 32,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 48, color: AppColors.medium),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20), textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(message, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5), textAlign: TextAlign.center),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
