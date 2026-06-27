import 'package:flutter/material.dart';
import 'package:scope/widgets/scope_card.dart';

/// Today's brief — action counts, deadlines, and estimated review time.
class DailyBriefCard extends StatelessWidget {
  final int reviewedCount;
  final int actionCount;
  final int deadlineCount;
  final int financialUpdateCount;
  final int estimatedMinutes;
  final VoidCallback? onStartFocus;
  final bool canStartFocus;

  const DailyBriefCard({
    super.key,
    required this.reviewedCount,
    required this.actionCount,
    required this.deadlineCount,
    required this.financialUpdateCount,
    required this.estimatedMinutes,
    this.onStartFocus,
    this.canStartFocus = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ScopeCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Today's Brief", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            reviewedCount == 0
                ? 'Waiting for notifications to review.'
                : 'AI reviewed today\'s notifications.',
            style: theme.textTheme.bodyLarge,
          ),
          if (reviewedCount > 0) ...[
            const SizedBox(height: 20),
            Text('You have', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (actionCount > 0) _BriefLine(icon: Icons.bolt_outlined, text: '$actionCount action${actionCount == 1 ? '' : 's'} today'),
            if (deadlineCount > 0) _BriefLine(icon: Icons.event_outlined, text: '$deadlineCount deadline${deadlineCount == 1 ? '' : 's'}'),
            if (financialUpdateCount > 0) _BriefLine(icon: Icons.payments_outlined, text: '$financialUpdateCount financial update${financialUpdateCount == 1 ? '' : 's'}'),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Text(
                  'Estimated review time · $estimatedMinutes minute${estimatedMinutes == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: canStartFocus ? onStartFocus : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: Text(
                canStartFocus ? 'Start Focus Session' : 'Nothing to review',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BriefLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
