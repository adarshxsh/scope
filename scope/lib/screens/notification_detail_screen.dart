import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/widgets/ai_reason_widget.dart';
import 'package:scope/widgets/scope_card.dart';
import 'package:scope/widgets/smart_action_chip.dart';

/// Detail view — never auto-opens the originating app.
class NotificationDetailScreen extends StatelessWidget {
  final AppNotification notification;
  final NotificationController controller;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
    required this.controller,
  });

  String get _summary {
    if (notification.explanation != null && notification.explanation!.isNotEmpty) {
      return notification.explanation!.split('\n').first.replaceAll(RegExp(r'^[-•*]\s*'), '');
    }
    return notification.content.isNotEmpty
        ? notification.content
        : 'No additional summary available.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final features = notification.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notification.extractedFeatures!)
        : const ExtractedFeatures();
    final actions = SmartActions.forNotification(notification);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Action Detail'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            notification.title.isNotEmpty ? notification.title : notification.packageName,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          _Section(title: 'Original notification', child: Text(notification.content)),
          const SizedBox(height: 20),
          _Section(title: 'Summary', child: Text(_summary)),
          const SizedBox(height: 20),
          ScopeCard(
            padding: const EdgeInsets.all(20),
            child: AIReasonWidget(notification: notification),
          ),
          const SizedBox(height: 20),
          _Section(
            title: 'Extracted information',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (features.hasDeadline) _InfoRow(label: 'Deadline', value: 'Detected'),
                if (features.amount != null)
                  _InfoRow(label: 'Amount', value: '₹${features.amount}'),
                if (features.urls.isNotEmpty)
                  _InfoRow(label: 'Website', value: features.urls.first),
                if (features.phoneNumbers.isNotEmpty)
                  _InfoRow(label: 'Phone', value: features.phoneNumbers.first),
                if (features.emails.isNotEmpty)
                  _InfoRow(label: 'Email', value: features.emails.first),
                if (features.otp != null)
                  _InfoRow(label: 'Reference', value: '••••${features.otp!.substring(features.otp!.length > 2 ? features.otp!.length - 2 : 0)}'),
                _InfoRow(label: 'Organization', value: notification.packageName),
                if (!features.hasDeadline &&
                    features.amount == null &&
                    features.urls.isEmpty &&
                    features.phoneNumbers.isEmpty &&
                    features.emails.isEmpty)
                  Text('No structured data extracted.', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Suggested Actions', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actions
                .map(
                  (action) => SmartActionChip(
                    action: action,
                    onPressed: () => _handleAction(context, action),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Would open ${notification.packageName}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open Original App'),
          ),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, SmartAction action) {
    switch (action.type) {
      case SmartActionType.archive:
        controller.archive(notification.id);
        break;
      case SmartActionType.complete:
        controller.complete(notification.id);
        break;
      case SmartActionType.addCalendar:
        controller.recordCalendarEvent();
        break;
      case SmartActionType.remind:
        controller.recordReminder();
        break;
      default:
        controller.recordAction();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${action.label} recorded'), duration: const Duration(seconds: 1)),
      );
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
