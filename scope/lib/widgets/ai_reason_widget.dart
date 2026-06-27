import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';

/// Explains why a notification matters — derived from Ghost AI analysis.
class AIReasonWidget extends StatelessWidget {
  final AppNotification notification;

  const AIReasonWidget({super.key, required this.notification});

  List<String> get _reasons {
    final reasons = <String>[];
    final features = notification.extractedFeatures;

    if (features?['hasDeadline'] == true) {
      reasons.add('Deadline detected');
    }
    if (features?['amount'] != null) {
      reasons.add('Payment amount found');
    }
    if (features?['otp'] != null) {
      reasons.add('Security code detected');
    }
    if (notification.priority == 'critical' || notification.priority == 'high') {
      reasons.add('High priority classification');
    }
    if (notification.packageName.contains('gov')) {
      reasons.add('Official sender');
    }
    if (features?['urls'] is List && (features!['urls'] as List).isNotEmpty) {
      reasons.add('Action link available');
    }

    if (notification.explanation != null && notification.explanation!.isNotEmpty) {
      final lines = notification.explanation!
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^[-•*]\s*'), '').trim())
          .where((l) => l.isNotEmpty)
          .take(2);
      reasons.addAll(lines);
    }

    if (reasons.isEmpty) {
      reasons.add('Analyzed for relevance');
    }

    return reasons.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Why this matters', style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        ..._reasons.map(
          (reason) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(reason, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
