import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/theme/motion.dart';
import 'package:scope/widgets/motion/animated_count_text.dart';
import 'package:scope/widgets/scope_card.dart';

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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: AppMotion.slow,
              curve: AppMotion.enter,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: AppMotion.slow,
                  curve: AppMotion.emphasis,
                  builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded, size: 40, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Review Complete', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('Great work!', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 32),
                ScopeCard(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    children: [
                      _StatRow(
                        label: 'Notifications Reviewed',
                        value: stats.notificationsReviewed,
                      ),
                      _StatRow(label: 'Completed', value: stats.actionsCompleted),
                      _StatRow(label: 'Reminders Created', value: stats.remindersCreated),
                      _StatRow(label: 'Archived', value: stats.archived),
                      _StatRow(
                        label: 'Estimated Time Saved',
                        value: stats.estimatedMinutesSaved,
                        suffix: ' min',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: widget.onBackHome,
                    child: const Text('Back Home'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
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
  );
}
}

class _StatRow extends StatelessWidget {
  final String label;
  final int value;
  final String suffix;

  const _StatRow({
    required this.label,
    required this.value,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          AnimatedCountText(
            value: value,
            suffix: suffix,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}
