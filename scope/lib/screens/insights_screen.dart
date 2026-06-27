import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:scope/core/models/notification_model.dart';
import 'package:scope/core/state/notification_controller.dart';
import 'package:scope/core/utils/focus_area_mapper.dart';
import 'package:scope/theme/app_colors.dart';
import 'package:scope/theme/app_spacing.dart';
import 'package:scope/widgets/primitives/scope_icon_box.dart';
import 'package:scope/widgets/primitives/scope_row.dart';
import 'package:scope/widgets/primitives/scope_surface.dart';
import 'package:scope/widgets/scope_screen_body.dart';
import 'package:scope/widgets/section_header.dart';

/// Analytics overview using beautiful fl_charts.
class InsightsScreen extends StatefulWidget {
  final NotificationController controller;

  const InsightsScreen({super.key, required this.controller});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _touchedPieIndex = -1;
  int _touchedBarIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifications = widget.controller.notifications;
    final priorities = {'critical': 0, 'high': 0, 'medium': 0, 'low': 0};
    
    // Group by hour
    final hourlyVolume = List<int>.filled(24, 0);

    for (final n in notifications) {
      final p = n.priority ?? 'medium';
      priorities[p] = (priorities[p] ?? 0) + 1;
      
      final hour = DateTime.fromMillisecondsSinceEpoch(n.timestamp).hour;
      hourlyVolume[hour]++;
    }

    final focusCounts = widget.controller.focusAreaCounts;
    final withLatency = notifications.where((n) => n.latencyMs != null).toList();
    final avgLatency = withLatency.isEmpty
        ? 0
        : withLatency.map((n) => n.latencyMs!).fold<int>(0, (a, b) => a + b) ~/ withLatency.length;

    return SafeArea(
      child: ScopeScreenBody(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            const SectionHeader(
              title: 'Insights',
              subtitle: 'How your attention is distributed.',
            ),
            
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
                                  _touchedPieIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                });
                              },
                            ),
                            borderData: FlBorderData(show: false),
                            sectionsSpace: 4,
                            centerSpaceRadius: 60,
                            sections: _buildPieSections(priorities, notifications.length),
                          ),
                        ),
                        // Center text
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${notifications.length}',
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
                  Text('When you receive the most notifications', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
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
                                // Show title every 6 hours
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
                  Text('Analysis Overview', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  ScopeRow.info(label: 'Total captured', value: '${notifications.length}'),
                  ScopeRow.info(label: 'Needs action', value: '${widget.controller.needsAction.length}'),
                  ScopeRow.info(label: 'Completed today', value: '${widget.controller.completedToday.length}'),
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
