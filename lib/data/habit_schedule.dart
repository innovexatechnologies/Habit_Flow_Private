import 'habit.dart';

class HabitStreaks {
  const HabitStreaks({required this.current, required this.longest});

  final int current;
  final int longest;
}

enum HabitDayState { completed, missed, unscheduled, scheduled }

class TodayHabitSummary {
  const TodayHabitSummary({
    required this.activeCount,
    required this.scheduledHabits,
    required this.completedCount,
    required this.overallStreak,
  });

  final int activeCount;
  final List<Habit> scheduledHabits;
  final int completedCount;
  final int overallStreak;

  int get scheduledCount => scheduledHabits.length;
  int get remainingCount => scheduledCount - completedCount;
  int get completionPercent =>
      scheduledCount == 0 ? 0 : (completedCount * 100 / scheduledCount).round();
}

class HabitPeriodCounts {
  const HabitPeriodCounts({
    required this.scheduled,
    required this.completed,
    required this.missed,
  });

  final int scheduled;
  final int completed;
  final int missed;

  int? get completionPercent =>
      scheduled == 0 ? null : (completed * 100 / scheduled).round();
}

class HabitSchedule {
  static DateTime localDateFromKey(String key) {
    final parts = key.split('-').map(int.parse).toList(growable: false);
    if (parts.length != 3) {
      throw FormatException('Invalid local date key.', key);
    }
    return DateTime(parts[0], parts[1], parts[2]);
  }

  static HabitDayState dayState({
    required Habit habit,
    required Iterable<HabitCompletion> completions,
    required DateTime date,
    required DateTime asOf,
  }) {
    final day = _dateOnly(date);
    final today = _dateOnly(asOf);
    final created = _dateOnly(habit.createdAt);
    final archivedEnd = habit.status == HabitStatus.archived
        ? _dateOnly(habit.updatedAt)
        : null;
    if (day.isBefore(created) ||
        (archivedEnd != null && day.isAfter(archivedEnd))) {
      return HabitDayState.unscheduled;
    }
    if (day.isAfter(today)) {
      return habit.scheduleType != HabitScheduleType.weeklyTarget &&
              isScheduledOn(habit, day)
          ? HabitDayState.scheduled
          : HabitDayState.unscheduled;
    }

    final key = HabitCompletion.dateKey(day);
    final matching = completions.where(
      (completion) =>
          completion.habitId == habit.id && completion.localDate == key,
    );
    if (matching.any(
      (completion) => completion.status == CompletionStatus.completed,
    )) {
      return HabitDayState.completed;
    }
    if (matching.any(
      (completion) => completion.status == CompletionStatus.missed,
    )) {
      return HabitDayState.missed;
    }

    if (habit.scheduleType == HabitScheduleType.weeklyTarget) {
      if (day.weekday != DateTime.sunday) return HabitDayState.unscheduled;
      final weekStart = _mondayOf(day);
      if (weekStart.isBefore(created) || day.isAfter(today)) {
        return HabitDayState.unscheduled;
      }
      final weekCompletions = completions.where((completion) {
        if (completion.habitId != habit.id ||
            completion.status != CompletionStatus.completed) {
          return false;
        }
        final completedDate = localDateFromKey(completion.localDate);
        return !completedDate.isBefore(weekStart) &&
            !completedDate.isAfter(day);
      }).length;
      if (weekCompletions >= habit.weeklyTarget!) {
        return HabitDayState.unscheduled;
      }
      return day.isBefore(today)
          ? HabitDayState.missed
          : HabitDayState.scheduled;
    }

    if (!isScheduledOn(habit, day)) return HabitDayState.unscheduled;
    return day.isBefore(today) ? HabitDayState.missed : HabitDayState.scheduled;
  }

  static HabitHistorySummary summarizeHistory({
    required Habit habit,
    required Iterable<HabitCompletion> completions,
    required DateTime asOf,
  }) {
    final today = _dateOnly(asOf);
    var completed = 0;
    var missed = 0;
    var pendingWeeklySessions = 0;
    if (habit.scheduleType == HabitScheduleType.weeklyTarget) {
      final dates = completions
          .where(
            (completion) =>
                completion.habitId == habit.id &&
                completion.status == CompletionStatus.completed,
          )
          .map((completion) => completion.localDate)
          .toSet();
      final firstFullWeek = _mondayOf(habit.createdAt);
      final start = firstFullWeek.isBefore(_dateOnly(habit.createdAt))
          ? _addCalendarDays(firstFullWeek, 7)
          : firstFullWeek;
      final endDate =
          habit.status == HabitStatus.archived &&
              _dateOnly(habit.updatedAt).isBefore(today)
          ? _dateOnly(habit.updatedAt)
          : today;
      final lastFullWeek = _mondayOf(endDate).subtract(const Duration(days: 1));
      completed = dates.where((dateKey) {
        final date = localDateFromKey(dateKey);
        return !date.isBefore(_dateOnly(habit.createdAt)) &&
            !date.isAfter(endDate);
      }).length;
      for (
        var monday = start;
        !monday.isAfter(lastFullWeek);
        monday = _addCalendarDays(monday, 7)
      ) {
        var count = 0;
        for (var offset = 0; offset < 7; offset++) {
          if (dates.contains(
            HabitCompletion.dateKey(_addCalendarDays(monday, offset)),
          )) {
            count++;
          }
        }
        missed += (habit.weeklyTarget! - count).clamp(0, habit.weeklyTarget!);
      }
      if (habit.status == HabitStatus.active) {
        final currentWeekCompleted = dates.where((dateKey) {
          final date = localDateFromKey(dateKey);
          return !date.isBefore(_mondayOf(endDate)) && !date.isAfter(endDate);
        }).length;
        pendingWeeklySessions = (habit.weeklyTarget! - currentWeekCompleted)
            .clamp(0, habit.weeklyTarget!);
      }
    } else {
      final completedDates = completions
          .where(
            (completion) =>
                completion.habitId == habit.id &&
                completion.status == CompletionStatus.completed,
          )
          .map((completion) => completion.localDate)
          .toSet();
      final endDate =
          habit.status == HabitStatus.archived &&
              _dateOnly(habit.updatedAt).isBefore(today)
          ? _dateOnly(habit.updatedAt)
          : today;
      for (
        var date = _dateOnly(habit.createdAt);
        !date.isAfter(endDate);
        date = _addCalendarDays(date, 1)
      ) {
        if (!isScheduledOn(habit, date)) continue;
        final key = HabitCompletion.dateKey(date);
        if (completedDates.contains(key)) {
          completed++;
        } else if (date.isBefore(today)) {
          missed++;
        }
      }
    }
    final total = completed + missed + pendingWeeklySessions;
    return HabitHistorySummary(
      completedScheduledDays: completed,
      missedScheduledDays: missed,
      completionPercent: total == 0
          ? 0
          : (completed * 100 / total).round().clamp(0, 100),
    );
  }

  static HabitPeriodCounts summarizePeriod({
    required Habit habit,
    required Iterable<HabitCompletion> completions,
    required DateTime start,
    required DateTime end,
    required DateTime asOf,
  }) {
    final first = _dateOnly(start);
    final last = _dateOnly(end);
    if (last.isBefore(first)) {
      return const HabitPeriodCounts(scheduled: 0, completed: 0, missed: 0);
    }

    final records = completions
        .where((completion) => completion.habitId == habit.id)
        .toList(growable: false);
    var scheduled = 0;
    var completed = 0;
    var missed = 0;

    for (
      var date = first;
      !date.isAfter(last);
      date = _addCalendarDays(date, 1)
    ) {
      final state = dayState(
        habit: habit,
        completions: records,
        date: date,
        asOf: asOf,
      );
      if (habit.scheduleType == HabitScheduleType.weeklyTarget) {
        if (state == HabitDayState.completed) {
          completed++;
          scheduled++;
        } else if (state == HabitDayState.missed) {
          final monday = _mondayOf(date);
          final completedInWeek = records
              .where(
                (record) =>
                    record.status == CompletionStatus.completed &&
                    !localDateFromKey(record.localDate).isBefore(monday) &&
                    !localDateFromKey(record.localDate).isAfter(date),
              )
              .map((record) => record.localDate)
              .toSet()
              .length;
          final shortfall = (habit.weeklyTarget! - completedInWeek).clamp(
            0,
            habit.weeklyTarget!,
          );
          scheduled += shortfall;
          missed += shortfall;
        }
      } else {
        switch (state) {
          case HabitDayState.completed:
            scheduled++;
            completed++;
          case HabitDayState.missed:
            scheduled++;
            missed++;
          case HabitDayState.scheduled:
            scheduled++;
          case HabitDayState.unscheduled:
            break;
        }
      }
    }

    final today = _dateOnly(asOf);
    if (habit.scheduleType == HabitScheduleType.weeklyTarget &&
        habit.status == HabitStatus.active &&
        !last.isBefore(today)) {
      final monday = _mondayOf(today);
      if (!monday.isBefore(_mondayOf(first)) &&
          !monday.isAfter(_mondayOf(last))) {
        final completedThisWeek = records
            .where(
              (record) =>
                  record.status == CompletionStatus.completed &&
                  !localDateFromKey(record.localDate).isBefore(monday) &&
                  !localDateFromKey(record.localDate).isAfter(today),
            )
            .map((record) => record.localDate)
            .toSet()
            .length;
        scheduled += (habit.weeklyTarget! - completedThisWeek).clamp(
          0,
          habit.weeklyTarget!,
        );
      }
    }

    return HabitPeriodCounts(
      scheduled: scheduled,
      completed: completed,
      missed: missed,
    );
  }

  static bool isScheduledOn(Habit habit, DateTime date) {
    switch (habit.scheduleType) {
      case HabitScheduleType.daily:
        return true;
      case HabitScheduleType.selectedWeekdays:
        return habit.selectedWeekdays.contains(date.weekday);
      case HabitScheduleType.weeklyTarget:
        return true;
    }
  }

  static bool isScheduledForCheckIn({
    required Habit habit,
    required DateTime date,
    required Iterable<HabitCompletion> completions,
  }) {
    if (!isScheduledOn(habit, date)) return false;
    if (habit.scheduleType != HabitScheduleType.weeklyTarget) return true;

    final dateKey = HabitCompletion.dateKey(date);
    final completedDates = completions
        .where(
          (completion) =>
              completion.habitId == habit.id &&
              completion.status == CompletionStatus.completed,
        )
        .map((completion) => completion.localDate)
        .toSet();
    if (completedDates.contains(dateKey)) return true;

    return completedInWeekBefore(
          habitId: habit.id,
          completions: completions,
          date: date,
        ) <
        habit.weeklyTarget!;
  }

  static TodayHabitSummary summarizeToday({
    required List<Habit> activeHabits,
    required Map<String, List<HabitCompletion>> completionsByHabit,
    required List<HabitCompletion> todayCompletions,
    required DateTime asOf,
  }) {
    final completedIds = todayCompletions
        .where((completion) => completion.status == CompletionStatus.completed)
        .map((completion) => completion.habitId)
        .toSet();
    final scheduledHabits = activeHabits
        .where(
          (habit) => isScheduledForCheckIn(
            habit: habit,
            date: asOf,
            completions: completionsByHabit[habit.id] ?? const [],
          ),
        )
        .toList(growable: false);
    final scheduledIds = scheduledHabits.map((habit) => habit.id).toSet();
    final completedCount = scheduledIds.intersection(completedIds).length;

    return TodayHabitSummary(
      activeCount: activeHabits.length,
      scheduledHabits: scheduledHabits,
      completedCount: completedCount,
      overallStreak: _calculateOverallStreak(
        activeHabits: activeHabits,
        completionsByHabit: completionsByHabit,
        asOf: asOf,
      ),
    );
  }

  static HabitStreaks calculateOverallStreaks({
    required List<Habit> activeHabits,
    required Map<String, List<HabitCompletion>> completionsByHabit,
    required DateTime asOf,
  }) {
    if (activeHabits.isEmpty) return const HabitStreaks(current: 0, longest: 0);
    final today = _dateOnly(asOf);
    var earliest = today;
    for (final habit in activeHabits) {
      final created = _dateOnly(habit.createdAt);
      if (created.isBefore(earliest)) earliest = created;
    }

    final current = _calculateOverallStreak(
      activeHabits: activeHabits,
      completionsByHabit: completionsByHabit,
      asOf: today,
    );
    var longest = 0;
    var run = 0;
    for (
      var date = earliest;
      !date.isAfter(today);
      date = _addCalendarDays(date, 1)
    ) {
      final expected = _expectedOnDate(activeHabits, completionsByHabit, date);
      if (expected.isEmpty) continue;
      final allComplete = expected.every(
        (habit) => (completionsByHabit[habit.id] ?? const []).any(
          (completion) =>
              completion.localDate == HabitCompletion.dateKey(date) &&
              completion.status == CompletionStatus.completed,
        ),
      );
      if (date == today && !allComplete) continue;
      if (allComplete) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }
    return HabitStreaks(current: current, longest: longest);
  }

  static int _calculateOverallStreak({
    required List<Habit> activeHabits,
    required Map<String, List<HabitCompletion>> completionsByHabit,
    required DateTime asOf,
  }) {
    if (activeHabits.isEmpty) return 0;
    final today = _dateOnly(asOf);
    var earliest = today;
    for (final habit in activeHabits) {
      final created = _dateOnly(habit.createdAt);
      if (created.isBefore(earliest)) earliest = created;
    }

    var current = 0;
    for (
      var date = today;
      !date.isBefore(earliest);
      date = _addCalendarDays(date, -1)
    ) {
      final expected = _expectedOnDate(activeHabits, completionsByHabit, date);
      if (expected.isEmpty) continue;
      final allComplete = expected.every(
        (habit) => (completionsByHabit[habit.id] ?? const []).any(
          (completion) =>
              completion.localDate == HabitCompletion.dateKey(date) &&
              completion.status == CompletionStatus.completed,
        ),
      );
      if (date == today && !allComplete) continue;
      if (!allComplete) break;
      current++;
    }
    return current;
  }

  static List<Habit> _expectedOnDate(
    List<Habit> habits,
    Map<String, List<HabitCompletion>> completionsByHabit,
    DateTime date,
  ) {
    return habits
        .where((habit) {
          if (_dateOnly(habit.createdAt).isAfter(date)) return false;
          if (habit.status == HabitStatus.archived &&
              _dateOnly(habit.updatedAt).isBefore(date)) {
            return false;
          }
          final history = completionsByHabit[habit.id] ?? const [];
          if (habit.scheduleType != HabitScheduleType.weeklyTarget) {
            return isScheduledOn(habit, date);
          }
          if (history.any(
            (completion) =>
                completion.localDate == HabitCompletion.dateKey(date) &&
                completion.status == CompletionStatus.completed,
          )) {
            return true;
          }
          return completedInWeekBefore(
                habitId: habit.id,
                completions: history,
                date: date,
              ) <
              habit.weeklyTarget!;
        })
        .toList(growable: false);
  }

  static int completedInWeekBefore({
    required String habitId,
    required Iterable<HabitCompletion> completions,
    required DateTime date,
  }) {
    final monday = _mondayOf(date);
    final dateOnly = _dateOnly(date);
    return completions
        .where(
          (completion) =>
              completion.habitId == habitId &&
              completion.status == CompletionStatus.completed,
        )
        .where((completion) {
          final completedDate = localDateFromKey(completion.localDate);
          return !completedDate.isBefore(monday) &&
              completedDate.isBefore(dateOnly);
        })
        .map((completion) => completion.localDate)
        .toSet()
        .length;
  }

  static HabitStreaks calculateStreaks({
    required Habit habit,
    required Iterable<HabitCompletion> completions,
    required DateTime asOf,
  }) {
    final completedDates = completions
        .where(
          (completion) =>
              completion.habitId == habit.id &&
              completion.status == CompletionStatus.completed,
        )
        .map((completion) => completion.localDate)
        .toSet();

    return habit.scheduleType == HabitScheduleType.weeklyTarget
        ? _weeklyTargetStreaks(habit, completedDates, asOf)
        : _scheduledDayStreaks(habit, completedDates, asOf);
  }

  static HabitStreaks _scheduledDayStreaks(
    Habit habit,
    Set<String> completedDates,
    DateTime asOf,
  ) {
    final today = _dateOnly(asOf);
    final created = _dateOnly(habit.createdAt);
    var cursor = today;
    var current = 0;

    while (!cursor.isBefore(created)) {
      if (isScheduledOn(habit, cursor)) {
        final dateKey = HabitCompletion.dateKey(cursor);
        final isCompleted = completedDates.contains(dateKey);

        if (cursor == today && !isCompleted) {
          cursor = _addCalendarDays(cursor, -1);
          continue;
        }

        if (isCompleted) {
          current++;
        } else {
          break;
        }
      }
      cursor = _addCalendarDays(cursor, -1);
    }

    var longest = 0;
    var run = 0;
    for (
      var date = created;
      !date.isAfter(today);
      date = _addCalendarDays(date, 1)
    ) {
      if (!isScheduledOn(habit, date)) continue;
      if (completedDates.contains(HabitCompletion.dateKey(date))) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }

    return HabitStreaks(current: current, longest: longest);
  }

  static int completedInCurrentWeek({
    String? habitId,
    required Iterable<HabitCompletion> completions,
    required DateTime asOf,
  }) {
    final monday = _mondayOf(asOf);
    final sunday = monday.add(const Duration(days: 6));
    return completions
        .where(
          (completion) =>
              (habitId == null || completion.habitId == habitId) &&
              completion.status == CompletionStatus.completed &&
              !localDateFromKey(completion.localDate).isBefore(monday) &&
              !localDateFromKey(completion.localDate).isAfter(sunday),
        )
        .map((completion) => completion.localDate)
        .toSet()
        .length;
  }

  static HabitStreaks _weeklyTargetStreaks(
    Habit habit,
    Set<String> completedDates,
    DateTime asOf,
  ) {
    final target = habit.weeklyTarget!;
    final today = _dateOnly(asOf);
    final habitStart = _dateOnly(habit.createdAt);
    final currentWeek = _mondayOf(today);
    final firstFullWeek = _mondayOf(habitStart).isBefore(habitStart)
        ? _addCalendarDays(_mondayOf(habitStart), 7)
        : _mondayOf(habitStart);

    int completedInWeek(DateTime monday) {
      var count = 0;
      for (var offset = 0; offset < 7; offset++) {
        final date = monday.add(Duration(days: offset));
        if (!date.isBefore(habitStart) &&
            completedDates.contains(HabitCompletion.dateKey(date))) {
          count++;
        }
      }
      return count;
    }

    final currentQualified = completedInWeek(currentWeek) >= target;
    var current = 0;
    var week = currentQualified
        ? currentWeek
        : _addCalendarDays(currentWeek, -7);
    while (!week.isBefore(firstFullWeek) && completedInWeek(week) >= target) {
      current++;
      week = _addCalendarDays(week, -7);
    }

    var longest = 0;
    var run = 0;
    for (
      week = firstFullWeek;
      !week.isAfter(currentWeek);
      week = _addCalendarDays(week, 7)
    ) {
      if (week == currentWeek && !currentQualified) continue;
      if (completedInWeek(week) >= target) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }

    return HabitStreaks(current: current, longest: longest);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _mondayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);

  static DateTime _addCalendarDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);
}
