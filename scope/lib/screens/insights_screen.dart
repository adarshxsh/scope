import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/privacy_budget_manager.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_row.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

class _PrivacyInsightsData {
  final Map<String, NoisedQueryResult<int>> priorities;
  final List<NoisedQueryResult<num>> hourlyVolume;
  final NoisedQueryResult<int> totalCaptured;
  final Map<FocusArea, NoisedQueryResult<int>> focusCounts;
  final NoisedQueryResult<int> focusDuration;
  final PrivacyBudgetStatus status;

  _PrivacyInsightsData({
    required this.priorities,
    required this.hourlyVolume,
    required this.totalCaptured,
    required this.focusCounts,
    required this.focusDuration,
    required this.status,
  });
}

/// Analytics overview using differential privacy protected fl_charts.
class InsightsScreen extends StatefulWidget {
  final NotificationController controller;

  const InsightsScreen({super.key, required this.controller});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _touchedPieIndex = -1;
  int _touchedBarIndex = -1;
  late Future<_PrivacyInsightsData> _insightsFuture;

  @override
  void initState() {
    super.initState();
    _insightsFuture = _fetchPrivacyProtectedData();
  }

  Future<_PrivacyInsightsData> _fetchPrivacyProtectedData() async {
    final status = await widget.controller.getPrivacyBudgetStatus();
    final priorities = await widget.controller.getNoisedPriorityDistribution();
    final hourly = await widget.controller.getNoisedHourlyVolume();
    final totalCaptured = await widget.controller.getNoisedTotalCapturedCount();
    final focusCounts = await widget.controller.getNoisedFocusAreaCounts();
    final focusDuration = await widget.controller.getNoisedTotalFocusDuration();

    return _PrivacyInsightsData(
      priorities: priorities,
      hourlyVolume: hourly,
      totalCaptured: totalCaptured,
      focusCounts: focusCounts,
      focusDuration: focusDuration,
      status: status,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifications = widget.controller.notifications;

    final withLatency = notifications.where((n) => n.latencyMs != null).toList();
    final avgLatency = withLatency.isEmpty
        ? 0
        : withLatency.map((n) => n.latencyMs!).fold<int>(0, (a, b) => a + b) ~/ withLatency.length;

    return SafeArea(
      child: ScopeScreenBody(
        child: FutureBuilder<_PrivacyInsightsData>(
          future: _insightsFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;

            // Fallback default or loading state data if waiting
            final priorityMap = <String, int>{
              'critical': data?.priorities['critical']?.noisedInt ?? 0,
              'high': data?.priorities['high']?.noisedInt ?? 0,
              'medium': data?.priorities['medium']?.noisedInt ?? 0,
              'low': data?.priorities['low']?.noisedInt ?? 0,
            };

            final hourlyVolume = data?.hourlyVolume.map((e) => e.noisedValue.round()).toList() ??
                List<int>.filled(24, 0);

            final totalCapturedDisplay = data?.totalCaptured.isBudgetExhausted == true
                ? (data?.totalCaptured.coarsenedBounds ?? '~')
                : '${data?.totalCaptured.noisedInt ?? notifications.length}';

            final isExhausted = data?.status.isExhausted ?? false;

            return ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                const SectionHeader(
                  title: 'Insights',
                  subtitle: 'How your attention is distributed (DP Protected).',
                ),

                // Privacy Budget Ledger Banner / Exhaustion Indicator
                if (data != null) ...[
                  ScopeSurface(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          isExhausted ? Icons.warning_amber_rounded : Icons.shield,
                          color: isExhausted ? Colors.orangeAccent : AppColors.seed,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isExhausted
                                    ? 'Privacy Budget Exhausted'
                                    : 'Differential Privacy Active',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: isExhausted ? Colors.orangeAccent : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isExhausted
                                    ? 'Daily budget limit (${data.status.dailyCap.toStringAsFixed(1)} ε) exceeded. Displaying coarsened bounds.'
                                    : 'Remaining budget today: ${data.status.remainingDaily.toStringAsFixed(2)} / ${data.status.dailyCap.toStringAsFixed(1)} ε',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Priority Pie Chart
                ScopeSurface(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Priority Distribution', style: theme.textTheme.titleMedium),
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
                                      _touchedPieIndex =
                                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                                    });
                                  },
                                ),
                                borderData: FlBorderData(show: false),
                                sectionsSpace: 4,
                                centerSpaceRadius: 60,
                                sections: _buildPieSections(priorityMap, notifications.length),
                              ),
                            ),
                            // Center text
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  totalCapturedDisplay,
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Total',
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
                      Text('When you receive the most notifications',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
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
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontWeight: FontWeight.normal),
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
                              leftTitles:
                                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles:
                                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles:
                                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                      Text('Analysis Overview', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      ScopeRow.info(label: 'Total captured', value: totalCapturedDisplay),
                      ScopeRow.info(
                          label: 'Needs action', value: '${widget.controller.needsAction.length}'),
                      ScopeRow.info(
                          label: 'Completed today',
                          value: '${widget.controller.completedToday.length}'),
                      ScopeRow.info(label: 'Avg AI latency (ms)', value: '$avgLatency'),
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
                          final countResult = data?.focusCounts[area];
                          final countStr = countResult?.isBudgetExhausted == true
                              ? (countResult?.coarsenedBounds ?? '~')
                              : '${countResult?.noisedInt ?? widget.controller.focusAreaCounts[area] ?? 0}';

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
                                Text(countStr, style: theme.textTheme.titleSmall),
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
                      ..._generateDynamicInsights(
                          notifications,
                          hourlyVolume,
                          data?.focusCounts
                                  .map((k, v) => MapEntry(k, v.noisedInt)) ??
                              widget.controller.focusAreaCounts,
                          theme),
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
    if (total == 0) {
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
              toY: 0, // We could make this the max volume if we wanted a background track
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
