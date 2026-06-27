import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_row.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';

/// Completion screen after a Focus review session.
class FocusCompleteScreen extends StatefulWidget {
  final ReviewSessionStats stats;
  final VoidCallback onBackHome;
  final VoidCallback onReviewAgain;

  const FocusCompleteScreen({
    super.key,
    required this.stats,
    required this.onBackHome,
    required this.onReviewAgain,
  });

  @override
  State<FocusCompleteScreen> createState() => _FocusCompleteScreenState();
}

class _FocusCompleteScreenState extends State<FocusCompleteScreen> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(AppMotion.fast, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = widget.stats;

    return Scaffold(
      body: SafeArea(
        child: ScopeScreenBody(
          child: Center(
            child: SingleChildScrollView(
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: AppMotion.slow,
                curve: AppMotion.enter,
                child: Column(
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.9, end: 1),
                      duration: AppMotion.slow,
                      curve: AppMotion.emphasis,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: ScopeIconBox(
                        icon: Icons.check_rounded,
                        size: ScopeIconBoxSize.lg,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Review Complete', style: theme.textTheme.headlineLarge),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Great work!', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      '${stats.notificationsReviewed}',
                      style: theme.textTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'notifications reviewed',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    ScopeSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      child: Column(
                        children: [
                          ScopeRow.metric(label: 'Completed', count: stats.actionsCompleted),
                          ScopeRow.metric(label: 'Reminders Created', count: stats.remindersCreated),
                          ScopeRow.metric(label: 'Archived', count: stats.archived),
                          ScopeRow.metric(
                            label: 'Estimated Time Saved',
                            count: stats.estimatedMinutesSaved,
                            valueSuffix: ' min',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: widget.onBackHome,
                        child: const Text('Back Home'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: widget.onReviewAgain,
                        child: const Text('Review Again'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
