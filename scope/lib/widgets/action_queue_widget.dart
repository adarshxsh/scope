import 'package:flutter/material.dart';
import 'package:scope/widgets/summary_card.dart';

/// Horizontal row of action queue summary cards.
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
          accentColor: const Color(0xFFE65100),
          onTap: onQueueTap == null ? null : () => onQueueTap!('needs'),
        ),
        const SizedBox(height: 10),
        SummaryCard(
          label: 'Important',
          count: important,
          icon: Icons.flag_outlined,
          accentColor: const Color(0xFF1565C0),
          onTap: onQueueTap == null ? null : () => onQueueTap!('important'),
        ),
        const SizedBox(height: 10),
        SummaryCard(
          label: 'Archived',
          count: archived,
          icon: Icons.inventory_2_outlined,
          accentColor: const Color(0xFF78909C),
          onTap: onQueueTap == null ? null : () => onQueueTap!('archived'),
        ),
      ],
    );
  }
}
