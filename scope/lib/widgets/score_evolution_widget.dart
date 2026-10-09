import 'package:flutter/material.dart';
import 'package:scope/core/analysis/score_evolution_trace.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';

/// Displays the score evolution trace through classification stages.
class ScoreEvolutionWidget extends StatelessWidget {
  final AppNotification notification;
  final ScoreEvolutionTrace? trace;

  const ScoreEvolutionWidget({
    super.key,
    required this.notification,
    this.trace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveTrace = trace ?? _fallbackTrace();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Score Evolution Trace',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        ScopeSurface(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: effectiveTrace.steps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              final isLast = index == effectiveTrace.steps.length - 1;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: isLast
                          ? AppColors.urgency(notification.priority)
                          : theme.primaryColor.withValues(alpha: 0.2),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isLast ? Colors.white : theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                step.stageName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${(step.score * 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.urgency(notification.priority),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            step.description,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (step.trigger != null && step.trigger != 'none')
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Trigger: ${step.trigger}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.amber.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (!isLast) const Divider(height: AppSpacing.md),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  ScoreEvolutionTrace _fallbackTrace() {
    final score = notification.priorityScore ?? 0.5;
    return ScoreEvolutionTrace(
      steps: [
        ScoreEvolutionStep(
          stageName: 'NLP Classification',
          score: score,
          description: 'Categorized as ${notification.classifiedCategory ?? "general"}',
        ),
        ScoreEvolutionStep(
          stageName: 'Policy Engine',
          score: score,
          description: 'Assigned priority ${notification.priority?.toUpperCase() ?? "MEDIUM"}',
        ),
      ],
      finalPriority: notification.priority ?? 'medium',
      finalScore: score,
    );
  }
}
