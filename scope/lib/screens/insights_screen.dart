import 'package:flutter/material.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/theme/app_theme.dart';
import 'package:scope/widgets/scope_card.dart';

/// Analytics overview — priority distribution and focus area breakdown.
class InsightsScreen extends StatelessWidget {
  final NotificationController controller;

  const InsightsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifications = controller.notifications;
    final priorities = <String, int>{
      'critical': 0,
      'high': 0,
      'medium': 0,
      'low': 0,
    };

    for (final n in notifications) {
      final p = n.priority ?? 'medium';
      priorities[p] = (priorities[p] ?? 0) + 1;
    }

    final focusCounts = controller.focusAreaCounts;
    final withLatency = notifications.where((n) => n.latencyMs != null).toList();
    final avgLatency = withLatency.isEmpty
        ? 0
        : withLatency.map((n) => n.latencyMs!).fold<int>(0, (a, b) => a + b) ~/
            withLatency.length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Insights', style: theme.textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(
            'How your attention is distributed.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ScopeCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overview', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                _MetricRow(label: 'Total captured', value: '${notifications.length}'),
                _MetricRow(label: 'Needs action', value: '${controller.needsAction.length}'),
                _MetricRow(label: 'Completed today', value: '${controller.completedToday.length}'),
                _MetricRow(label: 'Avg analysis (ms)', value: '$avgLatency'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ScopeCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Priority distribution', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                ...priorities.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PriorityBar(
                      label: e.key,
                      count: e.value,
                      total: notifications.length,
                      color: AppTheme.urgencyColor(e.key),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ScopeCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Focus areas', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                ...FocusArea.values.map(
                  (area) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(area.icon, size: 16),
                            const SizedBox(width: 8),
                            Text(area.label),
                          ],
                        ),
                        Text('${focusCounts[area]}'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _PriorityBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _PriorityBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(), style: Theme.of(context).textTheme.bodySmall),
            Text('$count', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.1),
            color: color,
          ),
        ),
      ],
    );
  }
}
