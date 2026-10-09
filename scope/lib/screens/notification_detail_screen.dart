import 'package:flutter/material.dart';
import 'package:scope/core/analysis/extracted_features.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/smart_actions.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/ai_reason_widget.dart';
import 'package:scope/widgets/primitives/scope_row.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';
import 'package:scope/widgets/smart_action_chip.dart';

/// Detail view — never auto-opens the originating app.
class NotificationDetailScreen extends StatefulWidget {
  final AppNotification notification;
  final NotificationController controller;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
    required this.controller,
  });

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  AppNotification? _unredactedNotification;

  @override
  void initState() {
    super.initState();
    _loadUnredacted();
  }

  Future<void> _loadUnredacted() async {
    try {
      final fetched = await widget.controller.getNotificationById(widget.notification.id);
      if (mounted && fetched != null) {
        setState(() {
          _unredactedNotification = fetched;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  String _getSummary(AppNotification notif) {
    if (notif.explanation != null && notif.explanation!.isNotEmpty) {
      return notif.explanation!.split('\n').first.replaceAll(RegExp(r'^[-•*]\s*'), '');
    }
    return notif.content.isNotEmpty
        ? notif.content
        : 'No additional summary available.';
  }

  @override
  Widget build(BuildContext context) {
    final notif = _unredactedNotification ?? widget.notification;
    final theme = Theme.of(context);
    final features = notif.extractedFeatures != null
        ? ExtractedFeatures.fromMap(notif.extractedFeatures!)
        : const ExtractedFeatures();
    final actions = SmartActions.forNotification(notif);
    final urgencyColor = AppColors.urgency(notif.priority);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghost AI Analysis'),
        centerTitle: true,
      ),
      body: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: urgencyColor.withValues(alpha: 0.15),
                  child: Icon(Icons.apps, color: urgencyColor),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notif.title.isNotEmpty ? notif.title : notif.packageName,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        notif.packageName,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (notif.priority != null && notif.priority != 'low')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: urgencyColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: urgencyColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      notif.priority!.toUpperCase(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: urgencyColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Why this matters', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.lg),
              borderColor: urgencyColor.withValues(alpha: 0.3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getSummary(notif), style: theme.textTheme.bodyLarge),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  AIReasonWidget(notification: notif),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Suggested Actions', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: actions
                  .map(
                    (action) => SmartActionChip(
                      action: action,
                      onPressed: () => _handleAction(context, action, notif),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text('Under the hood', style: theme.textTheme.titleMedium),
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                children: [
                  ScopeSurface(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailSection(title: 'Raw Message', child: Text(notif.content, style: theme.textTheme.bodyMedium)),
                        const SizedBox(height: AppSpacing.md),
                        _DetailSection(
                          title: 'What I found',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (features.hasDeadline)
                                const ScopeInfoRow(label: 'Deadline', value: 'Detected'),
                              if (features.amount != null)
                                ScopeInfoRow(label: 'Amount', value: '₹${features.amount}'),
                              if (features.urls.isNotEmpty)
                                ScopeInfoRow(label: 'Website', value: features.urls.first),
                              if (features.phoneNumbers.isNotEmpty)
                                ScopeInfoRow(label: 'Phone', value: features.phoneNumbers.first),
                              if (features.emails.isNotEmpty)
                                ScopeInfoRow(label: 'Email', value: features.emails.first),
                              ScopeInfoRow(label: 'Organization', value: notif.packageName),
                              if (!features.hasDeadline &&
                                  features.amount == null &&
                                  features.urls.isEmpty &&
                                  features.phoneNumbers.isEmpty &&
                                  features.emails.isEmpty)
                                Text('No structured data extracted.', style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, SmartAction action, AppNotification notif) {
    bool shouldPop = false;
    switch (action.type) {
      case SmartActionType.archive:
        widget.controller.archive(notif.id);
        shouldPop = true;
        break;
      case SmartActionType.complete:
        widget.controller.complete(notif.id);
        shouldPop = true;
        break;
      case SmartActionType.addCalendar:
        widget.controller.saveActionItem(notif, action);
        widget.controller.recordCalendarEvent();
        shouldPop = true;
        break;
      case SmartActionType.remind:
        widget.controller.saveActionItem(notif, action);
        widget.controller.recordReminder();
        shouldPop = true;
        break;
      case SmartActionType.track:
        widget.controller.saveActionItem(notif, action);
        widget.controller.recordAction();
        shouldPop = true;
        break;
      default:
        widget.controller.recordAction();
        widget.controller.complete(notif.id); // Mark complete since we are executing it
        shouldPop = true;
        break;
    }
    
    if (context.mounted) {
      final isGeneric = action.type == SmartActionType.archive || 
                        action.type == SmartActionType.complete ||
                        action.type == SmartActionType.addCalendar ||
                        action.type == SmartActionType.remind ||
                        action.type == SmartActionType.track;
      
      final msg = isGeneric 
          ? '${action.label} recorded'
          : 'Opening App for: ${action.label}...';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
      
      if (shouldPop && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label: title),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}
