import 'package:flutter/material.dart';
import 'package:scope/theme/app_spacing.dart';

/// Unified loading indicator.
class ScopeLoading extends StatelessWidget {
  final String? message;
  final bool compact;

  const ScopeLoading({super.key, this.message, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: compact ? 24 : 28,
            height: compact ? 24 : 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(message!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
