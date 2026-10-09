import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/privacy/dp_telemetry_service.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/state/providers.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/database/database_provider.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_row.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Analytics overview using fl_charts with Differential Privacy noise injection & sensitivity clipping.
class InsightsScreen extends StatefulWidget {
  final NotificationController controller;

  const InsightsScreen({super.key, required this.controller});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _touchedPieIndex = -1;
  int _touchedBarIndex = -1;

  bool _isLoadingDp = true;
  DpQueryResult<Map<String, int>>? _priorityResult;
  DpQueryResult<List<int>>? _hourlyVolumeResult;
  DpQueryResult<Map<String, dynamic>>? _overviewStatsResult;
  DpQueryResult<NoisyFocusSessionMetrics>? _focusSessionResult;

  @override
  void initState() {
    super.initState();
    _loadDpTelemetry();
  }

  @override
  void didUpdateWidget(InsightsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadDpTelemetry();
  }

  Future<void> _loadDpTelemetry() async {
    final notifications = widget.controller.notifications;
    final dpService = widget.controller.dpTelemetryService;

    // Group raw priorities
    final rawPriorities = {'critical': 0, 'high': 0, 'medium': 0, 'low': 0};
    final rawHourly = List<int>.filled(24, 0);

    for (final n in notifications) {
      final p = n.priority ?? 'medium';
      rawPriorities[p] = (rawPriorities[p] ?? 0) + 1;

      final hour = DateTime.fromMillisecondsSinceEpoch(n.timestamp).hour;
      rawHourly[hour]++;
    }

    final withLatency = notifications.where((n) => n.latencyMs != null).toList();
    final avgLatency = withLatency.isEmpty
        ? 0
        : withLatency.map((n) => n.latencyMs!).fold<int>(0, (a, b) => a + b) ~/ withLatency.length;

    final db = providerContainer.read(databaseProvider);
    final focusSessions = await db.focusSessionDao.getAll();

    final priorityRes = await dpService.queryPriorityDistribution(rawPriorities);
    final hourlyRes = await dpService.queryHourlyVolume(rawHourly);
    final overviewRes = await dpService.queryOverviewStats(
      totalCaptured: notifications.length,
      needsActionCount: widget.controller.needsAction.length,
      completedTodayCount: widget.controller.completedToday.length,
      avgLatencyMs: avgLatency,
    );
    final focusRes = await dpService.queryFocusSessionMetrics(focusSessions);

    if (mounted) {
      setState(() {
        _priorityResult = priorityRes;
        _hourlyVolumeResult = hourlyRes;
        _overviewStatsResult = overviewRes;
        _focusSessionResult = focusRes;
        _isLoadingDp = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifications = widget.controller.notifications;
    final focusCounts = widget.controller.focusAreaCounts;

    if (_isLoadingDp || _priorityResult == null) {
      return const SafeArea(
        child: ScopeScreenBody(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final priorities = _priorityResult!.data;
    final totalPrioritiesCount = priorities.values.fold<int>(0, (a, b) => a + b);
    final hourlyVolume = _hourlyVolumeResult!.data;
    final overview = _overviewStatsResult!.data;
    final focusMetrics = _focusSessionResult!.data;
    final isExhausted = _priorityResult!.isBudgetExhausted ||
        _hourlyVolumeResult!.isBudgetExhausted ||
        _overviewStatsResult!.isBudgetExhausted ||
        widget.controller.privacyBudgetManager.isBudgetExhausted();

    return SafeArea(
      child: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Insights',
              subtitle: 'How your attention is distributed.',
            ),

            // Privacy Budget Status Card
            ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    isExhausted ? Icons.lock_clock_outlined : Icons.shield_outlined,
                    color: isExhausted ? Colors.amber : AppColors.medium,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isExhausted
                              ? 'Privacy Budget Limit Reached'
                              : 'Differential Privacy Active',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isExhausted ? Colors.amber : Colors.white,
                          ),
                        ),
                        Text(
                          isExhausted
                              ? '0.00 / ${widget.controller.privacyBudgetManager.getMaxEpsilon().toStringAsFixed(2)} ε remaining — Presenting bounded DP approximations'
                              : '${widget.controller.privacyBudgetManager.getRemainingEpsilon().toStringAsFixed(2)} / ${widget.controller.privacyBudgetManager.getMaxEpsilon().toStringAsFixed(2)} ε remaining — Noise injected',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

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
                      Text('Differentially Private', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.medium)),
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
                            sections: _buildPieSections(priorities, totalPrioritiesCount),
                          ),
                        ),
                        // Center text
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$totalPrioritiesCount',
                              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
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
                  Text('When you receive the most notifications (Laplace noised)', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
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

            // Focus Sessions Telemetry Card
            ScopeSurface(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Focus Session Telemetry', style: theme.textTheme.titleMedium),
                      const Icon(Icons.timer_outlined, color: AppColors.medium, size: 20),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ScopeRow.info(
                    label: 'Total session duration',
                    value: isExhausted
                        ? (_focusSessionResult?.bucketedRanges?['duration'] ?? '15 – 30 mins')
                        : '${(focusMetrics.totalDurationSeconds / 60).round()} mins',
                  ),
                  ScopeRow.info(
                    label: 'Interruption count',
                    value: isExhausted
                        ? (_focusSessionResult?.bucketedRanges?['interruptions'] ?? '1 – 2 interruptions')
                        : '${focusMetrics.totalInterruptions}',
                  ),
                  ScopeRow.info(
                    label: 'Sessions completed',
                    value: '${focusMetrics.sessionCount}',
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
                  ScopeRow.info(
                    label: 'Total captured',
                    value: isExhausted
                        ? (_overviewStatsResult?.bucketedRanges?['totalCaptured'] ?? '${overview['totalCaptured']}')
                        : '${overview['totalCaptured']}',
                  ),
                  ScopeRow.info(
                    label: 'Needs action',
                    value: isExhausted
                        ? (_overviewStatsResult?.bucketedRanges?['needsActionCount'] ?? '${overview['needsActionCount']}')
                        : '${overview['needsActionCount']}',
                  ),
                  ScopeRow.info(
                    label: 'Completed today',
                    value: isExhausted
                        ? (_overviewStatsResult?.bucketedRanges?['completedTodayCount'] ?? '${overview['completedTodayCount']}')
                        : '${overview['completedTodayCount']}',
                  ),
                  ScopeRow.info(
                    label: 'Avg AI latency (ms)',
                    value: '${overview['avgLatencyMs']}',
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
                    (area) => Padding(
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
                          Text('${focusCounts[area]}', style: theme.textTheme.titleSmall),
                        ],
                      ),
                    ),
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
