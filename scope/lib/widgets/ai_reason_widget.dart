import 'package:flutter/material.dart';
import 'package:scope/core/analysis/feature_attribution.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';

/// Explains why a notification matters using dynamic feature attributions and override traces.
class AIReasonWidget extends StatelessWidget {
  final AppNotification notification;
  final bool inverted;

  const AIReasonWidget({
    super.key,
    required this.notification,
    this.inverted = false,
  });

  List<String> get _reasons {
    final reasons = <String>[];
    final features = notification.extractedFeatures;

    // Check for structured feature attributions attached during analysis
    final rawAttributions = features?['featureAttributions'] as List?;
    if (rawAttributions != null && rawAttributions.isNotEmpty) {
      for (final raw in rawAttributions) {
        if (raw is Map<String, dynamic>) {
          final attr = FeatureAttribution.fromMap(raw);
          if (attr.description.isNotEmpty) {
            reasons.add(attr.description);
          }
        }
      }
    }

    // Check for override triggers
    final trigger = features?['overrideTrigger'] as String?;
    if (trigger != null && trigger != 'none') {
      switch (trigger) {
        case 'expired_otp':
          reasons.add('Security passcode expiration window passed.');
          break;
        case 'expired_deadline':
          reasons.add('Relative deadline/reminder time has passed.');
          break;
        case 'duplicate':
          reasons.add('Duplicate notification within 5-minute sliding window.');
          break;
        case 'completed_task':
          reasons.add('Resolved or completed task notification.');
          break;
        case 'critical_bypass':
          reasons.add('Matched critical security or financial rule.');
          break;
      }
    }

    if (reasons.isEmpty) {
      if (features?['hasDeadline'] == true) reasons.add("There's a deadline coming up.");
      if (features?['amount'] != null) reasons.add('Payment transaction detected.');
      if (features?['otp'] != null) reasons.add('Sensitive verification passcode detected.');
      if (notification.priority == 'critical' || notification.priority == 'high') {
        reasons.add('Elevated priority score assigned.');
      }
      if (notification.packageName.contains('gov')) reasons.add('Official government communication.');
    }

    if (notification.explanation != null && notification.explanation!.isNotEmpty && reasons.length < 2) {
      final lines = notification.explanation!
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^[-•*]\s*'), '').trim())
          .where((l) => l.isNotEmpty && !l.startsWith('Priority resolved') && !l.startsWith('• Category') && !l.startsWith('• Source'))
          .take(2);
      reasons.addAll(lines);
    }

    if (reasons.isEmpty) reasons.add('Evaluated using Ghost AI natural language classification.');
    return reasons.toSet().take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = inverted
        ? theme.textTheme.titleSmall?.copyWith(color: Colors.white)
        : theme.textTheme.titleSmall;
    final bodyStyle = inverted
        ? theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72))
        : theme.textTheme.bodyMedium;
    final iconColor = inverted ? Colors.white38 : AppColors.muted(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Why this matters', style: titleStyle),
        const SizedBox(height: AppSpacing.sm),
        ..._reasons.map(
          (reason) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: iconColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(reason, style: bodyStyle)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
