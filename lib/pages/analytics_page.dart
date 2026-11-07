import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_widgets.dart';
import '../data/habit_analytics.dart';
import '../data/habit_controller.dart';

enum _AnalyticsRange { week, month, custom }

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({required this.controller, super.key});

  final HabitController controller;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  _AnalyticsRange _range = _AnalyticsRange.week;
  DateTime _selectedDate = DateTime.now();
  late DateTime _rangeStart = _defaultRangeStart();
  DateTime _rangeEnd = _dateOnly(DateTime.now());
  bool _includeArchived = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _dateOnly(DateTime.now());
    final range = _selectedRange(today);
    final report = HabitAnalyticsReport.build(
      habits: widget.controller.allHabits,
      completionsByHabit: widget.controller.allCompletionsByHabit,
      startDate: range.$1,
      endDate: range.$2,
      asOf: today,
      includeArchived: _includeArchived,
    );

    return AppPage(
      children: [
        const SectionHeading(
          title: 'Analytics',
          subtitle: 'A clear view of the consistency you’re building.',
        ),
        const SizedBox(height: 18),
        SegmentedButton<_AnalyticsRange>(
          segments: const [
            ButtonSegment(value: _AnalyticsRange.week, label: Text('Week')),
            ButtonSegment(value: _AnalyticsRange.month, label: Text('Month')),
            ButtonSegment(
              value: _AnalyticsRange.custom,
              label: Text('Date range'),
            ),
          ],
          selected: {_range},
          onSelectionChanged: (selection) =>
              setState(() => _range = selection.first),
        ),
        const SizedBox(height: 12),
        _PeriodSelector(
          range: _range,
          selectedDate: _selectedDate,
          rangeStart: _rangeStart,
          rangeEnd: _rangeEnd,
          onSelectDate: _selectDate,
          onSelectRangeDate: _selectRangeDate,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            avatar: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Include archived history'),
            selected: _includeArchived,
            onSelected: (value) => setState(() => _includeArchived = value),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SELECTED PERIOD', style: theme.textTheme.labelSmall),
                const SizedBox(height: 5),
                Text(
                  _periodLabel(report.startDate, report.endDate),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _AnalyticsMetric(
                        label: 'Completion',
                        value: report.completionPercent == null
                            ? '—'
                            : '${report.completionPercent}%',
                        detail: report.counts.scheduled == 0
                            ? 'No scheduled check-ins'
                            : '${report.counts.completed} of ${report.counts.scheduled} scheduled',
                        icon: Icons.donut_large_rounded,
                        accent: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _AnalyticsMetric(
                        label: 'Missed',
                        value: '${report.counts.missed}',
                        detail: 'Ended scheduled check-ins',
                        icon: Icons.event_busy_outlined,
                        accent: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AnalyticsMetricCard(
                label: 'Current streak',
                value: '${report.streaks.current}',
                unit: 'days',
                icon: Icons.local_fire_department_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AnalyticsMetricCard(
                label: 'Longest streak',
                value: '${report.streaks.longest}',
                unit: 'days',
                icon: Icons.emoji_events_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (report.counts.scheduled == 0)
          const AppEmptyState(
            icon: Icons.insights_outlined,
            title: 'No scheduled check-ins yet',
            message: 'Choose another period or add a habit to see your progress here.',
          )
        else ...[
          _TrendChartCard(
            title: 'Weekly completion trend',
            subtitle: 'Completion by weekday in the selected period',
            points: report.weeklyTrend,
          ),
          const SizedBox(height: 12),
          _TrendChartCard(
            title: 'Monthly completion trend',
            subtitle:
                report.monthlyTrend.any(
                  (point) => point.label.startsWith('Week'),
                )
                ? 'Weekly totals in the selected period'
                : 'Monthly totals in the selected period',
            points: report.monthlyTrend,
          ),
          if (report.bestHabit != null) ...[
            const SizedBox(height: 24),
            const SectionHeading(
              title: 'Habit performance',
              subtitle: 'Comparison is based on scheduled check-ins.',
            ),
            const SizedBox(height: 12),
            if (report.bestHabit case final best?)
              _PerformanceInsight(
                label: 'Best-performing habit',
                entry: best,
                icon: Icons.star_outline_rounded,
                color: theme.colorScheme.primary,
              ),
            if (report.lowConsistencyHabit case final low?) ...[
              const SizedBox(height: 10),
              _PerformanceInsight(
                label: 'Low-consistency habit',
                entry: low,
                icon: Icons.trending_down_rounded,
                color: theme.colorScheme.tertiary,
              ),
            ],
          ],
          if (report.habits.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeading(
              title: 'Habit comparison',
              subtitle: 'Scheduled completions and all-time streaks.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < report.habits.length; index++)
                    _HabitComparisonRow(
                      entry: report.habits[index],
                      isLast: index == report.habits.length - 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  (DateTime, DateTime) _selectedRange(DateTime today) {
    switch (_range) {
      case _AnalyticsRange.week:
        final monday = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day - _selectedDate.weekday + 1,
        );
        final sunday = DateTime(monday.year, monday.month, monday.day + 6);
        return (monday, sunday.isAfter(today) ? today : sunday);
      case _AnalyticsRange.month:
        final first = DateTime(_selectedDate.year, _selectedDate.month);
        final last = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
        return (first, last.isAfter(today) ? today : last);
      case _AnalyticsRange.custom:
        return (_rangeStart, _rangeEnd.isAfter(today) ? today : _rangeEnd);
    }
  }

  Future<void> _selectDate() async {
    final today = _dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(today) ? today : _selectedDate,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: _range == _AnalyticsRange.week
          ? 'Choose a date in the week'
          : 'Choose a month',
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedDate = _dateOnly(selected));
  }

  Future<void> _selectRangeDate({required bool start}) async {
    final today = _dateOnly(DateTime.now());
    final current = start ? _rangeStart : _rangeEnd;
    final selected = await showDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: start ? 'Choose start date' : 'Choose end date',
    );
    if (selected == null || !mounted) return;
    final date = _dateOnly(selected);
    setState(() {
      if (start) {
        _rangeStart = date;
        if (_rangeEnd.isBefore(date)) _rangeEnd = date;
      } else {
        _rangeEnd = date;
        if (_rangeStart.isAfter(date)) _rangeStart = date;
      }
    });
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.range,
    required this.selectedDate,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onSelectDate,
    required this.onSelectRangeDate,
  });

  final _AnalyticsRange range;
  final DateTime selectedDate;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final VoidCallback onSelectDate;
  final Future<void> Function({required bool start}) onSelectRangeDate;

  @override
  Widget build(BuildContext context) {
    switch (range) {
      case _AnalyticsRange.week:
        final monday = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day - selectedDate.weekday + 1,
        );
        final sunday = DateTime(monday.year, monday.month, monday.day + 6);
        return OutlinedButton.icon(
          onPressed: onSelectDate,
          icon: const Icon(Icons.date_range_rounded),
          label: Text(
            '${_shortDate(monday)} – ${_shortDate(sunday)}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      case _AnalyticsRange.month:
        return OutlinedButton.icon(
          onPressed: onSelectDate,
          icon: const Icon(Icons.calendar_month_rounded),
          label: Text(_monthLabel(selectedDate)),
        );
      case _AnalyticsRange.custom:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => onSelectRangeDate(start: true),
                child: Text(
                  'From ${_shortDate(rangeStart)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => onSelectRangeDate(start: false),
                child: Text(
                  'To ${_shortDate(rangeEnd)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _AnalyticsMetric extends StatelessWidget {
  const _AnalyticsMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(value, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 3),
        Text(detail, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _AnalyticsMetricCard extends StatelessWidget {
  const _AnalyticsMetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 3),
                  Text(
                    '$value $unit',
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChartCard extends StatelessWidget {
  const _TrendChartCard({
    required this.title,
    required this.subtitle,
    required this.points,
  });

  final String title;
  final String subtitle;
  final List<HabitAnalyticsPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduledPoints = points
        .where((point) => point.counts.scheduled > 0)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 3),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 14),
            if (scheduledPoints.isEmpty)
              Text(
                'No scheduled check-ins in this period.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              _ChartLegend(
                completedColor: theme.colorScheme.primary,
                remainingColor: theme.colorScheme.outline.withValues(
                  alpha: 0.55,
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final chartWidth = math
                      .max(constraints.maxWidth, points.length * 52.0)
                      .toDouble();
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Semantics(
                      container: true,
                      label: points
                          .map((point) {
                            final counts = point.counts;
                            return '${point.label}: ${counts.completed} completed of '
                                '${counts.scheduled} scheduled';
                          })
                          .join('. '),
                      child: SizedBox(
                        width: chartWidth,
                        height: 224,
                        child: Column(
                          children: [
                            Expanded(
                              child: BarChart(
                                BarChartData(
                                  minY: 0,
                                  maxY: _maxScheduled(points),
                                  alignment: BarChartAlignment.spaceAround,
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    horizontalInterval: _gridInterval(points),
                                    getDrawingHorizontalLine: (value) => FlLine(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.24),
                                      strokeWidth: 1,
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 28,
                                        getTitlesWidget: (value, meta) => Text(
                                          value.toInt().toString(),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                letterSpacing: 0,
                                                fontSize: 9,
                                              ),
                                        ),
                                      ),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 30,
                                        getTitlesWidget: (value, meta) {
                                          final index = value.toInt();
                                          if (index < 0 ||
                                              index >= points.length) {
                                            return const SizedBox.shrink();
                                          }
                                          return SideTitleWidget(
                                            meta: meta,
                                            space: 5,
                                            child: Text(
                                              points[index].label,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    letterSpacing: 0,
                                                    fontSize: 9,
                                                  ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  barTouchData: BarTouchData(
                                    enabled: true,
                                    touchTooltipData: BarTouchTooltipData(
                                      getTooltipItem:
                                          (group, groupIndex, rod, rodIndex) {
                                            final point = points[groupIndex];
                                            final counts = point.counts;
                                            final percent =
                                                counts.completionPercent;
                                            return BarTooltipItem(
                                              '${point.label}\n'
                                              '${counts.completed} of ${counts.scheduled} · '
                                              '${percent == null ? 'No scheduled check-ins' : '$percent%'}',
                                              TextStyle(
                                                color: theme
                                                    .colorScheme
                                                    .onInverseSurface,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            );
                                          },
                                    ),
                                  ),
                                  barGroups: [
                                    for (
                                      var index = 0;
                                      index < points.length;
                                      index++
                                    )
                                      _barGroup(
                                        index,
                                        points[index],
                                        theme.colorScheme.primary,
                                        theme.colorScheme.outline.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            SizedBox(
                              height: 16,
                              child: Row(
                                children: [
                                  for (final point in points)
                                    SizedBox(
                                      width: chartWidth / points.length,
                                      child: Text(
                                        point.counts.scheduled == 0
                                            ? '—'
                                            : '${point.counts.completed}/${point.counts.scheduled}',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              letterSpacing: 0,
                                              fontSize: 9,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

BarChartGroupData _barGroup(
  int index,
  HabitAnalyticsPoint point,
  Color completedColor,
  Color remainingColor,
) {
  final counts = point.counts;
  final total = counts.scheduled.toDouble();
  final done = counts.completed.toDouble();
  return BarChartGroupData(
    x: index,
    barRods: [
      BarChartRodData(
        toY: total,
        width: 20,
        borderRadius: BorderRadius.circular(4),
        color: remainingColor,
        rodStackItems: total == 0
            ? const []
            : [
                BarChartRodStackItem(0, done, completedColor),
                if (total > done)
                  BarChartRodStackItem(done, total, remainingColor),
              ],
      ),
    ],
  );
}

double _maxScheduled(List<HabitAnalyticsPoint> points) {
  final maximum = points.fold<int>(
    0,
    (value, point) => math.max(value, point.counts.scheduled),
  );
  return (maximum + (maximum == 0 ? 1 : 0)).toDouble();
}

double _gridInterval(List<HabitAnalyticsPoint> points) {
  final maximum = points.fold<int>(
    0,
    (value, point) => math.max(value, point.counts.scheduled),
  );
  return maximum <= 5 ? 1 : (maximum / 5).ceilToDouble();
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.completedColor,
    required this.remainingColor,
  });

  final Color completedColor;
  final Color remainingColor;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _LegendItem(color: completedColor, label: 'Completed'),
        _LegendItem(color: remainingColor, label: 'Scheduled, not completed'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PerformanceInsight extends StatelessWidget {
  const _PerformanceInsight({
    required this.label,
    required this.entry,
    required this.icon,
    required this.color,
  });

  final String label;
  final HabitAnalyticsHabit entry;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: theme.textTheme.labelLarge),
        subtitle: Text(
          '${entry.habit.name} · ${entry.counts.completed}/'
          '${entry.counts.scheduled} scheduled check-ins',
        ),
        trailing: Text(
          '${entry.counts.completionPercent}%',
          style: theme.textTheme.titleLarge?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _HabitComparisonRow extends StatelessWidget {
  const _HabitComparisonRow({required this.entry, required this.isLast});

  final HabitAnalyticsHabit entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = entry.counts.completionPercent ?? 0;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.habit.name,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$percent%',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 7,
              backgroundColor: theme.colorScheme.outline.withValues(
                alpha: 0.22,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${entry.counts.completed} completed · '
            '${entry.counts.scheduled} scheduled · '
            '${entry.streaks.current} current / ${entry.streaks.longest} longest streak',
            style: theme.textTheme.bodyMedium,
          ),
          if (!isLast) ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.55),
            ),
          ],
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _defaultRangeStart() {
  final today = DateTime.now();
  return DateTime(today.year, today.month, today.day - 6);
}

String _periodLabel(DateTime start, DateTime end) {
  if (start == end) return _longDate(start);
  return '${_shortDate(start)} – ${_longDate(end)}';
}

String _shortDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

String _longDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _monthLabel(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}
