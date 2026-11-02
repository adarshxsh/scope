import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_budget_engine.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_row.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Analytics overview using privacy-budget aware telemetry queries.
class InsightsScreen extends StatefulWidget {
  final NotificationController controller;

  const InsightsScreen({super.key, required this.controller});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _touchedPieIndex = -1;
  int _touchedBarIndex = -1;

  late Future<Map<String, dynamic>> _telemetryFuture;

  @override
  void initState() {
    super.initState();
    _loadTelemetry();
  }

  @override
  void didUpdateWidget(covariant InsightsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _loadTelemetry();
    }
  }

  void _loadTelemetry() {
    _telemetryFuture = Future.wait([
      widget.controller.getNoisyPriorityDistribution(),
      widget.controller.getNoisyHourlyVolume(),
      widget.controller.getNoisyFocusAreaCounts(),
      widget.controller.getNoisyOverviewMetrics(),
    ]).then((results) {
      return {
        'priorities': results[0] as PrivacyQueryResult<Map<String, int>>,
        'hourlyVolume': results[1] as PrivacyQueryResult<List<int>>,
        'focusCounts': results[2] as PrivacyQueryResult<Map<FocusArea, int>>,
        'overview': results[3] as PrivacyQueryResult<Map<String, int>>,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifications = widget.controller.notifications;
    final budgetEngine = widget.controller.privacyBudgetEngine;

    return SafeArea(
      child: ScopeScreenBody(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _telemetryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.seed),
              );
            }

            final data = snapshot.data ?? {};
            final prioritiesRes = data['priorities'] as PrivacyQueryResult<Map<String, int>>?;
            final hourlyVolumeRes = data['hourlyVolume'] as PrivacyQueryResult<List<int>>?;
            final focusCountsRes = data['focusCounts'] as PrivacyQueryResult<Map<FocusArea, int>>?;
            final overviewRes = data['overview'] as PrivacyQueryResult<Map<String, int>>?;

            final isFallback = (prioritiesRes?.isFallback ?? false) ||
                (hourlyVolumeRes?.isFallback ?? false) ||
                (focusCountsRes?.isFallback ?? false) ||
                (overviewRes?.isFallback ?? false);

            final priorities = prioritiesRes?.value ?? {'critical': 0, 'high': 0, 'medium': 0, 'low': 0};
            final hourlyVolume = hourlyVolumeRes?.value ?? List<int>.filled(24, 0);
            final focusCounts = focusCountsRes?.value ?? {};
            final overview = overviewRes?.value ?? {};

            final totalCaptured = overview['totalCaptured'] ?? notifications.length;
            final needsActionCount = overview['needsAction'] ?? widget.controller.needsAction.length;
            final completedTodayCount = overview['completedToday'] ?? widget.controller.completedToday.length;
            final avgLatency = overview['avgLatencyMs'] ?? 0;

            return ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                const SectionHeader(
                  title: 'Insights',
                  subtitle: 'How your attention is distributed.',
                ),

                // Privacy Budget Status Indicator
                _buildPrivacyBudgetBanner(context, budgetEngine, isFallback),

                const SizedBox(height: AppSpacing.md),

                // Priority Pie Chart
                ScopeSurface(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Priority Distribution', style: theme.textTheme.titleMedium),
                          if (isFallback)
                            Text('Bucket Fallback', style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                pieTouchData: PieTouchData(
                                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                    setState(() {
                                      if (!event.isInterestedForInteractions ||
                                          pieTouchResponse == null ||
                                          pieTouchResponse.touchedSection == null) {
                                        _touchedPieIndex = -1;
                                        return;
                                      }
                                      _touchedPieIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                    });
                                  },
                                ),
                                borderData: FlBorderData(show: false),
                                sectionsSpace: 4,
                                centerSpaceRadius: 60,
                                sections: _buildPieSections(priorities, totalCaptured),
                              ),
                            ),
                            // Center text
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$totalCaptured',
                                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  isFallback ? 'Total (Bucket)' : 'Total (Noisy)',
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _buildLegend(),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Hourly Volume Bar Chart
                ScopeSurface(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hourly Volume', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        isFallback
                            ? 'When you receive notifications (Coarsened buckets applied)'
                            : 'When you receive notifications (Laplace noise injected)',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 200,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  return BarTooltipItem(
                                    '${rod.toY.round()} msgs\n',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    children: <TextSpan>[
                                      TextSpan(
                                        text: '${group.x.toString().padLeft(2, '0')}:00',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.normal),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              touchCallback: (FlTouchEvent event, barTouchResponse) {
                                setState(() {
                                  if (!event.isInterestedForInteractions ||
                                      barTouchResponse == null ||
                                      barTouchResponse.spot == null) {
                                    _touchedBarIndex = -1;
                                    return;
                                  }
                                  _touchedBarIndex = barTouchResponse.spot!.touchedBarGroupIndex;
                                });
                              },
                            ),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    if (value % 6 != 0) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        '${value.toInt().toString().padLeft(2, '0')}:00',
                                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                                      ),
                                    );
                                  },
                                  reservedSize: 28,
                                ),
                              ),
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: const FlGridData(show: false),
                            borderData: FlBorderData(show: false),
                            barGroups: _buildBarGroups(hourlyVolume),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Overview Analysis
                ScopeSurface(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Analysis Overview', style: theme.textTheme.titleMedium),
                          if (isFallback)
                            Text('Fallback Active', style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ScopeRow.info(
                        label: 'Total captured',
                        value: isFallback ? '$totalCaptured (coarsened)' : '$totalCaptured',
                      ),
                      ScopeRow.info(
                        label: 'Needs action',
                        value: isFallback ? '$needsActionCount (coarsened)' : '$needsActionCount',
                      ),
                      ScopeRow.info(
                        label: 'Completed today',
                        value: isFallback ? '$completedTodayCount (coarsened)' : '$completedTodayCount',
                      ),
                      ScopeRow.info(
                        label: 'Avg AI latency (ms)',
                        value: '$avgLatency',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Focus Areas
                ScopeSurface(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Focus Areas', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      ...FocusArea.values.map(
                        (area) {
                          final count = focusCounts[area] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    ScopeIconBox(icon: area.icon, size: ScopeIconBoxSize.sm),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(area.label, style: theme.textTheme.bodyMedium),
                                  ],
                                ),
                                Text('$count', style: theme.textTheme.titleSmall),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                // Ghost AI Insights
                ScopeSurface(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: AppColors.medium, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Text('Ghost AI Insights', style: theme.textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ..._generateDynamicInsights(notifications, hourlyVolume, focusCounts, theme),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPrivacyBudgetBanner(
    BuildContext context,
    PrivacyBudgetEngine budgetEngine,
    bool isFallback,
  ) {
    final theme = Theme.of(context);
    final remaining = budgetEngine.remainingBudget;
    final isDepleted = budgetEngine.isBudgetDepleted || isFallback;

    return ScopeSurface(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            isDepleted ? Icons.warning_amber_rounded : Icons.shield_rounded,
            color: isDepleted ? Colors.amber : AppColors.seed,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDepleted
                      ? 'Privacy Budget Depleted (Coarsened Fallback Active)'
                      : 'Privacy Budget Guard Active',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: isDepleted ? Colors.amber : AppColors.seed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDepleted
                      ? 'Daily epsilon budget exhausted (ε = 0.00). Coarsened bucket intervals presented without differential privacy noise.'
                      : 'Telemetry queries calibrated with Laplace noise. Remaining daily budget: ε = ${remaining.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _generateDynamicInsights(
    List<AppNotification> notifications,
    List<int> hourlyVolume,
    Map<FocusArea, int> focusCounts,
    ThemeData theme,
  ) {
    if (notifications.isEmpty) {
      return [Text('Not enough data to generate insights yet.', style: theme.textTheme.bodyMedium)];
    }

    final insights = <String>[];

    // Time saved insight
    final timeSaved = notifications.length * 2;
    if (timeSaved > 0) {
      insights.add('You saved roughly $timeSaved minutes today by batching notifications.');
    }

    // Peak hour insight
    var peakHour = 0;
    var maxVol = 0;
    for (var i = 0; i < hourlyVolume.length; i++) {
      if (hourlyVolume[i] > maxVol) {
        maxVol = hourlyVolume[i];
        peakHour = i;
      }
    }
    if (maxVol > 3) {
      final hourStr = peakHour == 12 ? '12 PM' : peakHour > 12 ? '${peakHour - 12} PM' : '${peakHour == 0 ? 12 : peakHour} AM';
      insights.add('Most of your interruptions happened around $hourStr ($maxVol notifications).');
    }

    // Top category insight
    var topArea = FocusArea.finance;
    var maxCount = 0;
    for (final entry in focusCounts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        topArea = entry.key;
      }
    }
    if (maxCount > 2) {
      insights.add('You had a high volume of ${topArea.label} notifications today.');
    }

    if (insights.isEmpty) {
      insights.add('Your notification volume is perfectly balanced today.');
    }

    return insights.map((insight) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.circle, size: 6, color: AppColors.medium),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(insight, style: theme.textTheme.bodyMedium)),
        ],
      ),
    )).toList();
  }

  List<PieChartSectionData> _buildPieSections(Map<String, int> priorities, int total) {
    if (total <= 0) {
      return [
        PieChartSectionData(
          color: AppColors.border,
          value: 1,
          title: '',
          radius: 20,
        )
      ];
    }

    int i = 0;
    return priorities.entries.map((e) {
      final isTouched = i == _touchedPieIndex;
      final fontSize = isTouched ? 16.0 : 0.0;
      final radius = isTouched ? 35.0 : 25.0;
      final value = e.value.toDouble();

      final data = PieChartSectionData(
        color: AppColors.urgency(e.key),
        value: value,
        title: isTouched && value > 0 ? '${e.value}' : '',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
      );
      i++;
      return data;
    }).toList();
  }

  List<BarChartGroupData> _buildBarGroups(List<int> hourlyVolume) {
    return List.generate(24, (i) {
      final isTouched = i == _touchedBarIndex;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: hourlyVolume[i].toDouble(),
            color: isTouched ? AppColors.seed : AppColors.seed.withValues(alpha: 0.5),
            width: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 0,
              color: Colors.transparent,
            ),
          ),
        ],
      );
    });
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _LegendItem(color: AppColors.critical, text: 'Critical'),
        _LegendItem(color: AppColors.high, text: 'High'),
        _LegendItem(color: AppColors.medium, text: 'Medium'),
        _LegendItem(color: AppColors.low, text: 'Low'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendItem({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }
}
