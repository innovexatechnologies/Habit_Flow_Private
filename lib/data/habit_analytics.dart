import 'habit.dart';
import 'habit_schedule.dart';

class HabitAnalyticsHabit {
  const HabitAnalyticsHabit({
    required this.habit,
    required this.counts,
    required this.streaks,
  });

  final Habit habit;
  final HabitPeriodCounts counts;
  final HabitStreaks streaks;
}

class HabitAnalyticsPoint {
  const HabitAnalyticsPoint({
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.counts,
  });

  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final HabitPeriodCounts counts;
}

class HabitAnalyticsReport {
  const HabitAnalyticsReport({
    required this.startDate,
    required this.endDate,
    required this.includedArchived,
    required this.habits,
    required this.counts,
    required this.streaks,
    required this.weeklyTrend,
    required this.monthlyTrend,
    required this.bestHabit,
    required this.lowConsistencyHabit,
  });

  final DateTime startDate;
  final DateTime endDate;
  final bool includedArchived;
  final List<HabitAnalyticsHabit> habits;
  final HabitPeriodCounts counts;
  final HabitStreaks streaks;
  final List<HabitAnalyticsPoint> weeklyTrend;
  final List<HabitAnalyticsPoint> monthlyTrend;
  final HabitAnalyticsHabit? bestHabit;
  final HabitAnalyticsHabit? lowConsistencyHabit;

  int? get completionPercent => counts.completionPercent;

  factory HabitAnalyticsReport.build({
    required List<Habit> habits,
    required Map<String, List<HabitCompletion>> completionsByHabit,
    required DateTime startDate,
    required DateTime endDate,
    required DateTime asOf,
    bool includeArchived = false,
  }) {
    final start = _dateOnly(startDate);
    final requestedEnd = _dateOnly(endDate);
    if (requestedEnd.isBefore(start)) {
      throw ArgumentError(
        'The analytics end date must not precede its start date.',
      );
    }

    final today = _dateOnly(asOf);
    final end = requestedEnd.isAfter(today) ? today : requestedEnd;
    final selectedHabits = habits
        .where((habit) => includeArchived || habit.status == HabitStatus.active)
        .toList(growable: false);
    final entries = <HabitAnalyticsHabit>[];
    var scheduled = 0;
    var completed = 0;
    var missed = 0;

    for (final habit in selectedHabits) {
      final records = completionsByHabit[habit.id] ?? const [];
      final habitStart = _later(start, _dateOnly(habit.createdAt));
      var habitEnd = end;
      if (habit.status == HabitStatus.archived) {
        habitEnd = _earlier(habitEnd, _dateOnly(habit.updatedAt));
      }
      final counts = habitEnd.isBefore(habitStart)
          ? const HabitPeriodCounts(scheduled: 0, completed: 0, missed: 0)
          : HabitSchedule.summarizePeriod(
              habit: habit,
              completions: records,
              start: habitStart,
              end: habitEnd,
              asOf: today,
            );
      final streaks = HabitSchedule.calculateStreaks(
        habit: habit,
        completions: records,
        asOf: habit.status == HabitStatus.archived
            ? _earlier(today, _dateOnly(habit.updatedAt))
            : today,
      );
      entries.add(
        HabitAnalyticsHabit(habit: habit, counts: counts, streaks: streaks),
      );
      scheduled += counts.scheduled;
      completed += counts.completed;
      missed += counts.missed;
    }

    final activeForStreak = selectedHabits
        .where((habit) {
          return habit.status == HabitStatus.active ||
              !today.isAfter(_dateOnly(habit.updatedAt));
        })
        .toList(growable: false);
    final streaks = HabitSchedule.calculateOverallStreaks(
      activeHabits: activeForStreak,
      completionsByHabit: completionsByHabit,
      asOf: today,
    );

    final eligible =
        entries
            .where((entry) => entry.counts.scheduled >= 3)
            .toList(growable: false)
          ..sort((a, b) {
            final percentOrder = (b.counts.completionPercent ?? 0).compareTo(
              a.counts.completionPercent ?? 0,
            );
            return percentOrder != 0
                ? percentOrder
                : a.habit.name.compareTo(b.habit.name);
          });
    final best = eligible.firstOrNull;
    HabitAnalyticsHabit? low;
    if (eligible.length > 1) {
      final lowest = eligible.last;
      final bestPercent = best!.counts.completionPercent!;
      final lowestPercent = lowest.counts.completionPercent!;
      if (lowestPercent < bestPercent && lowestPercent < 80) {
        low = lowest;
      }
    }

    final reportCounts = HabitPeriodCounts(
      scheduled: scheduled,
      completed: completed,
      missed: missed,
    );
    final reportHabits = entries
        .where((entry) => entry.counts.scheduled > 0)
        .toList(growable: false);

    return HabitAnalyticsReport(
      startDate: start,
      endDate: end,
      includedArchived: includeArchived,
      habits: reportHabits,
      counts: reportCounts,
      streaks: streaks,
      weeklyTrend: _buildWeekdayTrend(
        habits: selectedHabits,
        completionsByHabit: completionsByHabit,
        start: start,
        end: end,
        asOf: today,
      ),
      monthlyTrend: _buildMonthlyTrend(
        habits: selectedHabits,
        completionsByHabit: completionsByHabit,
        start: start,
        end: end,
        asOf: today,
      ),
      bestHabit: best,
      lowConsistencyHabit: low,
    );
  }
}

List<HabitAnalyticsPoint> _buildWeekdayTrend({
  required List<Habit> habits,
  required Map<String, List<HabitCompletion>> completionsByHabit,
  required DateTime start,
  required DateTime end,
  required DateTime asOf,
}) {
  if (end.isBefore(start)) return const [];
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final totals = List<int>.filled(7, 0);
  final completed = List<int>.filled(7, 0);
  final missed = List<int>.filled(7, 0);

  for (var date = start; !date.isAfter(end); date = _addDay(date)) {
    final index = date.weekday - 1;
    for (final habit in habits) {
      final counts = HabitSchedule.summarizePeriod(
        habit: habit,
        completions: completionsByHabit[habit.id] ?? const [],
        start: date,
        end: date,
        asOf: asOf,
      );
      totals[index] += counts.scheduled;
      completed[index] += counts.completed;
      missed[index] += counts.missed;
    }
  }

  return [
    for (var index = 0; index < labels.length; index++)
      HabitAnalyticsPoint(
        label: labels[index],
        startDate: start,
        endDate: end,
        counts: HabitPeriodCounts(
          scheduled: totals[index],
          completed: completed[index],
          missed: missed[index],
        ),
      ),
  ];
}

List<HabitAnalyticsPoint> _buildMonthlyTrend({
  required List<Habit> habits,
  required Map<String, List<HabitCompletion>> completionsByHabit,
  required DateTime start,
  required DateTime end,
  required DateTime asOf,
}) {
  if (end.isBefore(start)) return const [];
  final buckets = <(DateTime, DateTime, String)>[];
  final dayCount =
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;
  if (dayCount <= 31) {
    var bucketStart = start;
    var weekNumber = 1;
    while (!bucketStart.isAfter(end)) {
      final bucketEnd = _addDay(bucketStart, 6);
      final clippedEnd = _earlier(end, bucketEnd);
      buckets.add((bucketStart, clippedEnd, 'Week $weekNumber'));
      bucketStart = _addDay(bucketStart, 7);
      weekNumber++;
    }
  } else {
    var monthStart = DateTime(start.year, start.month);
    while (!monthStart.isAfter(end)) {
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
      buckets.add((
        _later(start, monthStart),
        _earlier(end, monthEnd),
        _monthLabel(monthStart),
      ));
      monthStart = DateTime(monthStart.year, monthStart.month + 1);
    }
  }

  return [
    for (final (bucketStart, bucketEnd, label) in buckets)
      _aggregateBucket(
        label: label,
        start: bucketStart,
        end: bucketEnd,
        habits: habits,
        completionsByHabit: completionsByHabit,
        asOf: asOf,
      ),
  ];
}

HabitAnalyticsPoint _aggregateBucket({
  required String label,
  required DateTime start,
  required DateTime end,
  required List<Habit> habits,
  required Map<String, List<HabitCompletion>> completionsByHabit,
  required DateTime asOf,
}) {
  var scheduled = 0;
  var completed = 0;
  var missed = 0;
  for (final habit in habits) {
    final habitStart = _later(start, _dateOnly(habit.createdAt));
    final habitEnd = habit.status == HabitStatus.archived
        ? _earlier(end, _dateOnly(habit.updatedAt))
        : end;
    if (habitEnd.isBefore(habitStart)) continue;
    final counts = HabitSchedule.summarizePeriod(
      habit: habit,
      completions: completionsByHabit[habit.id] ?? const [],
      start: habitStart,
      end: habitEnd,
      asOf: asOf,
    );
    scheduled += counts.scheduled;
    completed += counts.completed;
    missed += counts.missed;
  }
  return HabitAnalyticsPoint(
    label: label,
    startDate: start,
    endDate: end,
    counts: HabitPeriodCounts(
      scheduled: scheduled,
      completed: completed,
      missed: missed,
    ),
  );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _addDay(DateTime date, [int days = 1]) =>
    DateTime(date.year, date.month, date.day + days);

DateTime _later(DateTime left, DateTime right) =>
    left.isAfter(right) ? left : right;

DateTime _earlier(DateTime left, DateTime right) =>
    left.isBefore(right) ? left : right;

String _monthLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.year}';
}
