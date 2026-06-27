import 'package:flutter/material.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/summary_card.dart';

/// Vertical stack of action queue summary cards.
class ActionQueueWidget extends StatelessWidget {
  final int needsAction;
  final int important;
  final int archived;
  final void Function(String queue)? onQueueTap;

  const ActionQueueWidget({
    super.key,
    required this.needsAction,
    required this.important,
    required this.archived,
    this.onQueueTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SummaryCard(
          label: 'Needs Action',
          count: needsAction,
          icon: Icons.bolt_outlined,
          onTap: onQueueTap == null ? null : () => onQueueTap!('needs'),
        ),
        const SizedBox(height: AppSpacing.sm),
        SummaryCard(
          label: 'Important',
          count: important,
          icon: Icons.flag_outlined,
          onTap: onQueueTap == null ? null : () => onQueueTap!('important'),
        ),
        const SizedBox(height: AppSpacing.sm),
        SummaryCard(
          label: 'Archived',
          count: archived,
          icon: Icons.inventory_2_outlined,
          onTap: onQueueTap == null ? null : () => onQueueTap!('archived'),
        ),
      ],
    );
  }
}
