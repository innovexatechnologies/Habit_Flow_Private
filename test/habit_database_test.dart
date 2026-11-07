import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:habit_flow/data/habit.dart';
import 'package:habit_flow/data/habit_analytics.dart';
import 'package:habit_flow/data/habit_controller.dart';
import 'package:habit_flow/data/habit_database.dart';
import 'package:habit_flow/data/history_export_service.dart';
import 'package:habit_flow/data/habit_schedule.dart';

void main() {
  late String databasePath;
  late HabitDatabase database;
  late HabitRepository repository;
  late DateTime clock;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    clock = DateTime(2026, 11, 6, 12);
    databasePath = p.join(
      Directory.systemTemp.path,
      'habit-flow-${const Uuid().v4()}.db',
    );
    database = HabitDatabase(
      databasePath: databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    repository = HabitRepository(database, now: () => clock);
  });

  tearDown(() async {
    await database.close();
    final file = File(databasePath);
    if (await file.exists()) await file.delete();
  });

  test('habit and preferences survive closing and reopening SQLite', () async {
    final habit = Habit(
      name: 'Morning walk',
      description: 'Around the block',
      category: 'Health',
      scheduleType: HabitScheduleType.selectedWeekdays,
      selectedWeekdays: const [1, 3, 5],
      reminderEnabled: true,
      reminderTime: '07:30',
    );
    await repository.saveHabit(habit);
    await repository.savePreferences(
      const HabitPreferences(
        themeMode: ThemeMode.dark,
        reminderDefaultEnabled: true,
        reminderDefaultTime: '08:15',
      ),
    );
    await database.close();

    database = HabitDatabase(
      databasePath: databasePath,
      databaseFactory: databaseFactoryFfi,
    );
    repository = HabitRepository(database, now: () => clock);
    final savedHabits = await repository.getHabits();
    final savedPreferences = await repository.getPreferences();

    expect(savedHabits.single.id, habit.id);
    expect(savedHabits.single.selectedWeekdays, [1, 3, 5]);
    expect(savedHabits.single.reminderTime, '07:30');
    expect(savedPreferences.themeMode, ThemeMode.dark);
    expect(savedPreferences.reminderDefaultTime, '08:15');
  });

  test('completions are unique per habit and local calendar date', () async {
    final habit = Habit(name: 'Read', category: 'Learning');
    await repository.saveHabit(habit);
    final localDate = DateTime(2026, 11, 6, 23, 55);

    await repository.setCompletion(
      habitId: habit.id,
      date: localDate,
      status: CompletionStatus.completed,
    );
    final first = (await repository.getCompletionsForDate(localDate)).single;
    await repository.setCompletion(
      habitId: habit.id,
      date: DateTime(2026, 11, 6, 1),
      status: CompletionStatus.completed,
    );
    final records = await repository.getCompletionsForDate(localDate);

    expect(HabitCompletion.dateKey(localDate), '2026-11-06');
    expect(records, hasLength(1));
    expect(records.single.id, first.id);
    expect(records.single.localDate, '2026-11-06');
    expect(records.single.status, CompletionStatus.completed);
    expect(records.single.completedAt, isNotNull);
  });

  test('editing and archiving keeps completion history', () async {
    final habit = Habit(name: 'Stretch', category: 'Health');
    final date = DateTime(2026, 11, 5);
    clock = DateTime(2026, 11, 5, 12);
    await repository.saveHabit(habit);
    await repository.setCompletion(
      habitId: habit.id,
      date: date,
      status: CompletionStatus.completed,
    );
    final completionId = (await repository.getCompletionsForDate(date))
        .single
        .id;

    await repository.saveHabit(
      Habit(
        id: habit.id,
        name: 'Gentle stretch',
        category: 'Health',
        createdAt: habit.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
    await repository.archiveHabit(habit.id);

    expect(await repository.getHabits(), isEmpty);
    final archived = await repository.getHabits(includeArchived: true);
    expect(archived.single.status, HabitStatus.archived);
    final history = await repository.getRecentHistory();
    expect(history, hasLength(1));
    expect(history.single.habitName, 'Gentle stretch');
    expect(history.single.completion.id, completionId);
  });

  test('clear all is transactional and restores local defaults', () async {
    final habit = Habit(name: 'Journal', category: 'Mindfulness');
    await repository.saveHabit(habit);
    await repository.setCompletion(
      habitId: habit.id,
      date: DateTime(2026, 11, 6),
      status: CompletionStatus.completed,
    );
    await repository.savePreferences(
      const HabitPreferences(themeMode: ThemeMode.dark),
    );

    await repository.clearAllData();

    expect(await repository.getHabits(includeArchived: true), isEmpty);
    expect(await repository.getRecentHistory(), isEmpty);
    expect((await repository.getPreferences()).themeMode, ThemeMode.light);
  });

  test('controller initialization loads an empty offline state', () async {
    final controller = HabitController(repository);
    await controller.initialize();

    expect(controller.activeHabits, isEmpty);
    expect(controller.todayCompletions, isEmpty);
    expect(controller.history, isEmpty);

    controller.dispose();
  });

  test(
    'undo removes only today and preserves earlier completion records',
    () async {
      final habit = Habit(name: 'Read', category: 'Learning');
      await repository.saveHabit(habit);
      await repository.setCompletion(
        habitId: habit.id,
        date: clock,
        status: CompletionStatus.completed,
      );
      clock = DateTime(2026, 11, 7, 9);
      await repository.setCompletion(
        habitId: habit.id,
        date: clock,
        status: CompletionStatus.completed,
      );

      await repository.undoCompletion(habitId: habit.id, date: clock);

      expect(await repository.getCompletionsForDate(clock), isEmpty);
      expect(
        await repository.getCompletionsForDate(DateTime(2026, 11, 6)),
        hasLength(1),
      );
    },
  );

  test('check-ins are limited to today and scheduled weekdays', () async {
    clock = DateTime(2026, 11, 6, 12);
    final weekdaysHabit = Habit(
      name: 'Walk',
      category: 'Health',
      scheduleType: HabitScheduleType.selectedWeekdays,
      selectedWeekdays: const [1],
    );
    await repository.saveHabit(weekdaysHabit);

    await expectLater(
      repository.setCompletion(
        habitId: weekdaysHabit.id,
        date: clock,
        status: CompletionStatus.completed,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.setCompletion(
        habitId: weekdaysHabit.id,
        date: DateTime(2026, 11, 5),
        status: CompletionStatus.completed,
      ),
      throwsArgumentError,
    );
    expect(await repository.getCompletionsForHabit(weekdaysHabit.id), isEmpty);
  });

  test(
    'daily streak gives today a grace period but breaks after a missed day',
    () {
      final habit = Habit(
        id: 'daily',
        name: 'Read',
        category: 'Learning',
        createdAt: DateTime(2026, 11, 1),
      );
      final completions = [
        for (final day in [4, 5])
          HabitCompletion(
            habitId: habit.id,
            localDate: '2026-11-${day.toString().padLeft(2, '0')}',
            status: CompletionStatus.completed,
          ),
      ];

      final incompleteToday = HabitSchedule.calculateStreaks(
        habit: habit,
        completions: completions,
        asOf: DateTime(2026, 11, 6, 23, 59),
      );
      expect(incompleteToday.current, 2);
      expect(incompleteToday.longest, 2);

      final missedDayPassed = HabitSchedule.calculateStreaks(
        habit: habit,
        completions: completions,
        asOf: DateTime(2026, 11, 7),
      );
      expect(missedDayPassed.current, 0);
      expect(missedDayPassed.longest, 2);
    },
  );

  test('selected weekday streak ignores unscheduled days', () {
    final habit = Habit(
      id: 'weekdays',
      name: 'Walk',
      category: 'Health',
      scheduleType: HabitScheduleType.selectedWeekdays,
      selectedWeekdays: const [1, 3, 5],
      createdAt: DateTime(2026, 11, 2),
    );
    final completions = [
      for (final date in ['2026-11-02', '2026-11-04'])
        HabitCompletion(
          habitId: habit.id,
          localDate: date,
          status: CompletionStatus.completed,
        ),
    ];

    final streak = HabitSchedule.calculateStreaks(
      habit: habit,
      completions: completions,
      asOf: DateTime(2026, 11, 5),
    );
    expect(streak.current, 2);
    expect(streak.longest, 2);
    expect(HabitSchedule.isScheduledOn(habit, DateTime(2026, 11, 6)), true);
    expect(HabitSchedule.isScheduledOn(habit, DateTime(2026, 11, 7)), false);

    final afterMissedFriday = HabitSchedule.calculateStreaks(
      habit: habit,
      completions: completions,
      asOf: DateTime(2026, 11, 7),
    );
    expect(afterMissedFriday.current, 0);
    expect(afterMissedFriday.longest, 2);
  });

  test(
    'weekly target streak counts completed weeks and leaves current week open',
    () {
      final habit = Habit(
        id: 'weekly',
        name: 'Swim',
        category: 'Health',
        scheduleType: HabitScheduleType.weeklyTarget,
        weeklyTarget: 2,
        createdAt: DateTime(2026, 10, 26),
      );
      final completions = [
        for (final date in ['2026-10-26', '2026-10-28', '2026-11-02'])
          HabitCompletion(
            habitId: habit.id,
            localDate: date,
            status: CompletionStatus.completed,
          ),
      ];

      final streak = HabitSchedule.calculateStreaks(
        habit: habit,
        completions: completions,
        asOf: DateTime(2026, 11, 6),
      );
      expect(streak.current, 1);
      expect(streak.longest, 1);
      expect(
        HabitSchedule.completedInCurrentWeek(
          completions: completions,
          asOf: DateTime(2026, 11, 6),
        ),
        1,
      );

      completions.add(
        HabitCompletion(
          habitId: habit.id,
          localDate: '2026-11-04',
          status: CompletionStatus.completed,
        ),
      );
      final qualifiedWeek = HabitSchedule.calculateStreaks(
        habit: habit,
        completions: completions,
        asOf: DateTime(2026, 11, 6),
      );
      expect(qualifiedWeek.current, 2);
      expect(qualifiedWeek.longest, 2);
    },
  );

  test('an incomplete current day is not recorded as missed', () {
    clock = DateTime(2026, 11, 6, 23, 59);
    final habit = Habit(name: 'Journal', category: 'Mindfulness');

    final streak = HabitSchedule.calculateStreaks(
      habit: habit,
      completions: const [],
      asOf: clock,
    );
    expect(streak.current, 0);
    expect(streak.longest, 0);
  });

  test(
    'dashboard counts only scheduled active habits and real completions',
    () async {
      clock = DateTime(2026, 11, 6, 12);
      final daily = Habit(
        id: 'dashboard-daily',
        name: 'Read',
        category: 'Learning',
        createdAt: DateTime(2026, 11, 1),
      );
      final weekdays = Habit(
        id: 'dashboard-weekdays',
        name: 'Walk',
        category: 'Health',
        scheduleType: HabitScheduleType.selectedWeekdays,
        selectedWeekdays: const [1, 3, 5],
        createdAt: DateTime(2026, 11, 2),
      );
      final weekly = Habit(
        id: 'dashboard-weekly',
        name: 'Swim',
        category: 'Health',
        scheduleType: HabitScheduleType.weeklyTarget,
        weeklyTarget: 2,
        createdAt: DateTime(2026, 10, 26),
      );
      final archived = Habit(
        id: 'dashboard-archived',
        name: 'Old habit',
        category: 'Other',
        createdAt: DateTime(2026, 11, 1),
      );
      for (final habit in [daily, weekdays, weekly, archived]) {
        await repository.saveHabit(habit);
      }
      await repository.archiveHabit(archived.id);
      clock = DateTime(2026, 11, 6, 12);
      await repository.setCompletion(
        habitId: daily.id,
        date: clock,
        status: CompletionStatus.completed,
      );
      clock = DateTime(2026, 11, 4, 12);
      await repository.setCompletion(
        habitId: weekly.id,
        date: clock,
        status: CompletionStatus.completed,
      );
      clock = DateTime(2026, 11, 6, 12);

      final activeHabits = await repository.getHabits();
      final allCompletions = await repository.getCompletionsForHabits(
        activeHabits.map((habit) => habit.id).toList(),
      );
      final todayCompletions = await repository.getCompletionsForDate(clock);
      final summary = HabitSchedule.summarizeToday(
        activeHabits: activeHabits,
        completionsByHabit: allCompletions,
        todayCompletions: todayCompletions,
        asOf: clock,
      );

      expect(summary.activeCount, 3);
      expect(summary.scheduledCount, 3);
      expect(summary.completedCount, 1);
      expect(summary.remainingCount, 2);
      expect(summary.completionPercent, 33);
      expect(summary.scheduledHabits.map((habit) => habit.id).toSet(), {
        daily.id,
        weekdays.id,
        weekly.id,
      });
      expect(summary.overallStreak, 0);
    },
  );

  test(
    'dashboard has a safe zero-schedule percentage and friendly empty data',
    () {
      final summary = HabitSchedule.summarizeToday(
        activeHabits: const [],
        completionsByHabit: const {},
        todayCompletions: const [],
        asOf: clock,
      );

      expect(summary.activeCount, 0);
      expect(summary.scheduledCount, 0);
      expect(summary.completedCount, 0);
      expect(summary.remainingCount, 0);
      expect(summary.completionPercent, 0);
      expect(summary.overallStreak, 0);
    },
  );

  test('full history includes records for archived habits', () async {
    final active = Habit(name: 'Read', category: 'Learning');
    final archived = Habit(name: 'Stretch', category: 'Health');
    await repository.saveHabit(active);
    await repository.saveHabit(archived);
    for (final habit in [active, archived]) {
      await repository.setCompletion(
        habitId: habit.id,
        date: clock,
        status: CompletionStatus.completed,
      );
    }
    clock = DateTime(2026, 11, 7, 9);
    await repository.archiveHabit(archived.id);

    final allHistory = await repository.getAllHistory();

    expect(allHistory, hasLength(2));
    expect(allHistory.map((entry) => entry.habitName).toSet(), {
      'Read',
      'Stretch',
    });
    expect(
      (await repository.getHabits(includeArchived: true))
          .singleWhere((habit) => habit.id == archived.id)
          .status,
      HabitStatus.archived,
    );
  });

  test('history states and totals respect schedules and local date keys', () {
    final habit = Habit(
      id: 'history-weekdays',
      name: 'Walk',
      category: 'Health',
      scheduleType: HabitScheduleType.selectedWeekdays,
      selectedWeekdays: const [1, 3, 5],
      createdAt: DateTime(2026, 11, 2),
    );
    final records = [
      for (final date in ['2026-11-02', '2026-11-04'])
        HabitCompletion(
          habitId: habit.id,
          localDate: date,
          status: CompletionStatus.completed,
        ),
    ];
    final asOf = DateTime(2026, 11, 9, 0, 1);

    expect(
      HabitCompletion.dateKey(DateTime(2026, 11, 5, 23, 59)),
      '2026-11-05',
    );
    expect(
      HabitSchedule.dayState(
        habit: habit,
        completions: records,
        date: DateTime(2026, 11, 3),
        asOf: asOf,
      ),
      HabitDayState.unscheduled,
    );
    expect(
      HabitSchedule.dayState(
        habit: habit,
        completions: records,
        date: DateTime(2026, 11, 6),
        asOf: asOf,
      ),
      HabitDayState.missed,
    );
    expect(
      HabitSchedule.dayState(
        habit: habit,
        completions: records,
        date: DateTime(2026, 11, 9),
        asOf: asOf,
      ),
      HabitDayState.scheduled,
    );
    expect(
      HabitSchedule.dayState(
        habit: habit,
        completions: records,
        date: DateTime(2026, 11, 11),
        asOf: asOf,
      ),
      HabitDayState.scheduled,
    );
    final summary = HabitSchedule.summarizeHistory(
      habit: habit,
      completions: records,
      asOf: asOf,
    );
    expect(summary.completedScheduledDays, 2);
    expect(summary.missedScheduledDays, 1);
    expect(summary.completionPercent, 67);
  });

  test('weekly target miss is derived at week end, not stored by date', () {
    final habit = Habit(
      id: 'history-weekly',
      name: 'Swim',
      category: 'Health',
      scheduleType: HabitScheduleType.weeklyTarget,
      weeklyTarget: 2,
      createdAt: DateTime(2026, 10, 26),
    );
    final records = [
      for (final date in ['2026-10-26', '2026-10-28', '2026-11-04'])
        HabitCompletion(
          habitId: habit.id,
          localDate: date,
          status: CompletionStatus.completed,
        ),
    ];
    final asOf = DateTime(2026, 11, 9, 0, 1);

    expect(
      HabitSchedule.dayState(
        habit: habit,
        completions: records,
        date: DateTime(2026, 11, 8),
        asOf: asOf,
      ),
      HabitDayState.missed,
    );
    expect(
      HabitSchedule.dayState(
        habit: habit,
        completions: records,
        date: DateTime(2026, 11, 6),
        asOf: DateTime(2026, 11, 6, 23, 59),
      ),
      HabitDayState.unscheduled,
    );
    final summary = HabitSchedule.summarizeHistory(
      habit: habit,
      completions: records,
      asOf: asOf,
    );
    expect(summary.completedScheduledDays, 3);
    expect(summary.missedScheduledDays, 1);
    expect(summary.completionPercent, 50);
  });

  test(
    'exported month workbook opens with detailed and summary data',
    () async {
      final habit = Habit(
        id: 'export-daily',
        name: 'Morning pages',
        category: 'Mindfulness',
        createdAt: DateTime(2026, 11, 1),
      );
      clock = DateTime(2026, 11, 4, 8);
      await repository.saveHabit(habit);
      await repository.setCompletion(
        habitId: habit.id,
        date: clock,
        status: CompletionStatus.completed,
      );
      clock = DateTime(2026, 11, 6, 22, 30);
      await repository.setCompletion(
        habitId: habit.id,
        date: clock,
        status: CompletionStatus.completed,
      );
      final exportRoot = await Directory.systemTemp.createTemp(
        'habit-flow-xlsx-',
      );
      File? sharedFile;
      try {
        final service = HabitHistoryExportService(
          dataSource: repository,
          now: () => clock,
          documentsDirectory: () async => exportRoot,
          shareFile: (file) async {
            sharedFile = file;
            return const ShareResult(
              'spreadsheet-app',
              ShareResultStatus.success,
            );
          },
        );
        final result = await service.export(
          HistoryExportRequest(
            startDate: DateTime(2026, 11, 1),
            endDate: DateTime(2026, 11, 30),
          ),
        );

        expect(result.file.existsSync(), isTrue);
        expect(result.file.path, endsWith('HabitFlow_History_2026-11.xlsx'));
        expect(sharedFile?.path, result.file.path);
        expect(result.detailRowCount, 6);
        expect(result.summaryRowCount, 1);
        final workbook = Excel.decodeBytes(await result.file.readAsBytes());
        expect(workbook.tables.keys, containsAll(['History', 'Summary']));

        final detailRows = workbook.tables['History']!.rows;
        final summaryRows = workbook.tables['Summary']!.rows;
        String cellText(List<Data?>? row, int column) {
          final value = row![column]!.value;
          if (value is TextCellValue) return value.value.text ?? '';
          return value.toString();
        }

        expect(
          [
            for (var index = 0; index < 8; index++)
              cellText(detailRows.first, index),
          ],
          [
            'Date',
            'Habit ID',
            'Habit Name',
            'Category',
            'Scheduled',
            'Completion Status',
            'Completion Timestamp',
            'Current/Calculated Streak',
          ],
        );
        expect(detailRows, hasLength(7));
        expect(cellText(detailRows[1], 0), '2026-11-01');
        expect(cellText(detailRows[1], 4), 'Yes');
        expect(cellText(detailRows[1], 5), 'Missed');
        expect(cellText(detailRows[4], 0), '2026-11-04');
        expect(cellText(detailRows[4], 5), 'Completed');
        expect(cellText(detailRows[4], 6), '2026-11-04T08:00:00.000');
        expect(
          [
            for (var index = 0; index < 7; index++)
              cellText(summaryRows.first, index),
          ],
          [
            'Habit Name',
            'Date Range',
            'Scheduled Days',
            'Completed Days',
            'Missed Days',
            'Completion Percentage',
            'Longest Streak',
          ],
        );
        expect(summaryRows, hasLength(2));
        expect(cellText(summaryRows[1], 0), 'Morning pages');
        expect(cellText(summaryRows[1], 2), '6');
        expect(cellText(summaryRows[1], 3), '2');
        expect(cellText(summaryRows[1], 4), '4');
        expect(cellText(summaryRows[1], 5), '33%');
        expect(cellText(summaryRows[1], 6), '1');
      } finally {
        await exportRoot.delete(recursive: true);
      }
    },
  );

  test(
    'unfiltered history export includes every habit and shares the file',
    () async {
      clock = DateTime(2026, 11, 4, 12);
      final daily = Habit(
        id: 'export-all-daily',
        name: 'Daily reading',
        category: 'Learning',
        createdAt: DateTime(2026, 11, 4),
      );
      final weekdays = Habit(
        id: 'export-all-weekdays',
        name: 'Scheduled walk',
        category: 'Health',
        scheduleType: HabitScheduleType.selectedWeekdays,
        selectedWeekdays: const [DateTime.wednesday, DateTime.friday],
        createdAt: DateTime(2026, 11, 4),
      );
      await repository.saveHabit(daily);
      await repository.saveHabit(weekdays);
      for (final habit in [daily, weekdays]) {
        await repository.setCompletion(
          habitId: habit.id,
          date: clock,
          status: CompletionStatus.completed,
        );
      }
      clock = DateTime(2026, 11, 6, 12);

      final exportRoot = await Directory.systemTemp.createTemp(
        'habit-flow-xlsx-all-',
      );
      try {
        final result = await HabitHistoryExportService(
          dataSource: repository,
          now: () => clock,
          documentsDirectory: () async => exportRoot,
          shareFile: (_) async =>
              const ShareResult('spreadsheet-app', ShareResultStatus.success),
        ).export(const HistoryExportRequest());

        expect(result.file.existsSync(), isTrue);
        expect(result.shareResult.status, ShareResultStatus.success);
        expect(result.detailRowCount, 6);
        expect(result.summaryRowCount, 2);
        final workbook = Excel.decodeBytes(await result.file.readAsBytes());
        expect(workbook.tables['History']!.rows, hasLength(7));
        expect(workbook.tables['Summary']!.rows, hasLength(3));
      } finally {
        await exportRoot.delete(recursive: true);
      }
    },
  );

  test(
    'analytics trend totals match schedule summaries and workbook data',
    () async {
      clock = DateTime(2026, 11, 6, 12);
      final daily = Habit(
        id: 'analytics-daily',
        name: 'Daily reading',
        category: 'Learning',
        createdAt: DateTime(2026, 11, 2),
      );
      final weekdays = Habit(
        id: 'analytics-weekdays',
        name: 'Walk',
        category: 'Health',
        scheduleType: HabitScheduleType.selectedWeekdays,
        selectedWeekdays: const [
          DateTime.monday,
          DateTime.wednesday,
          DateTime.friday,
        ],
        createdAt: DateTime(2026, 11, 2),
      );
      final weeklyTarget = Habit(
        id: 'analytics-weekly-target',
        name: 'Swim',
        category: 'Health',
        scheduleType: HabitScheduleType.weeklyTarget,
        weeklyTarget: 2,
        createdAt: DateTime(2026, 10, 26),
      );
      final archived = Habit(
        id: 'analytics-archived',
        name: 'Archived practice',
        category: 'Mindfulness',
        createdAt: DateTime(2026, 11, 2),
      );
      for (final habit in [daily, weekdays, weeklyTarget, archived]) {
        await repository.saveHabit(habit);
      }
      for (final date in [DateTime(2026, 11, 2), DateTime(2026, 11, 3)]) {
        clock = date;
        await repository.setCompletion(
          habitId: daily.id,
          date: date,
          status: CompletionStatus.completed,
        );
      }
      for (final date in [DateTime(2026, 11, 2), DateTime(2026, 11, 4)]) {
        clock = date;
        await repository.setCompletion(
          habitId: weekdays.id,
          date: date,
          status: CompletionStatus.completed,
        );
      }
      for (final date in [DateTime(2026, 11, 3), DateTime(2026, 11, 5)]) {
        clock = date;
        await repository.setCompletion(
          habitId: weeklyTarget.id,
          date: date,
          status: CompletionStatus.completed,
        );
      }
      clock = DateTime(2026, 11, 2);
      await repository.setCompletion(
        habitId: archived.id,
        date: DateTime(2026, 11, 2),
        status: CompletionStatus.completed,
      );
      clock = DateTime(2026, 11, 4, 12);
      await repository.archiveHabit(archived.id);

      clock = DateTime(2026, 11, 6, 12);
      final allHabits = await repository.getHabits(includeArchived: true);
      final completions = await repository.getCompletionsForHabits(
        allHabits.map((habit) => habit.id).toList(),
      );
      final activeReport = HabitAnalyticsReport.build(
        habits: allHabits,
        completionsByHabit: completions,
        startDate: DateTime(2026, 11, 2),
        endDate: DateTime(2026, 11, 6),
        asOf: clock,
      );
      expect(activeReport.counts.scheduled, 10);
      expect(activeReport.counts.completed, 6);
      expect(activeReport.counts.missed, 2);
      expect(
        activeReport.habits.map((entry) => entry.habit.id),
        containsAll([daily.id, weekdays.id, weeklyTarget.id]),
      );
      expect(activeReport.habits, hasLength(3));

      final report = HabitAnalyticsReport.build(
        habits: allHabits,
        completionsByHabit: completions,
        startDate: DateTime(2026, 11, 2),
        endDate: DateTime(2026, 11, 6),
        asOf: clock,
        includeArchived: true,
      );
      expect(report.counts.scheduled, 13);
      expect(report.counts.completed, 7);
      expect(report.counts.missed, 4);
      expect(report.bestHabit?.habit.id, weekdays.id);
      expect(report.lowConsistencyHabit?.habit.id, archived.id);
      expect(
        report.habits.any((entry) => entry.habit.id == archived.id),
        isTrue,
      );
      expect(
        report.weeklyTrend.fold<int>(
          0,
          (sum, point) => sum + point.counts.scheduled,
        ),
        report.counts.scheduled,
      );
      expect(
        report.weeklyTrend.fold<int>(
          0,
          (sum, point) => sum + point.counts.completed,
        ),
        report.counts.completed,
      );
      expect(
        report.monthlyTrend.fold<int>(
          0,
          (sum, point) => sum + point.counts.missed,
        ),
        report.counts.missed,
      );
      var historyScheduled = 0;
      var historyCompleted = 0;
      var historyMissed = 0;
      for (final habit in allHabits) {
        final records = completions[habit.id] ?? const [];
        for (
          var date = DateTime(2026, 11, 2);
          !date.isAfter(DateTime(2026, 11, 6));
          date = DateTime(date.year, date.month, date.day + 1)
        ) {
          final state = HabitSchedule.dayState(
            habit: habit,
            completions: records,
            date: date,
            asOf: clock,
          );
          if (state == HabitDayState.unscheduled) continue;
          historyScheduled++;
          if (state == HabitDayState.completed) historyCompleted++;
          if (state == HabitDayState.missed) historyMissed++;
        }
      }
      expect(historyScheduled, report.counts.scheduled);
      expect(historyCompleted, report.counts.completed);
      expect(historyMissed, report.counts.missed);

      final exportRoot = await Directory.systemTemp.createTemp(
        'habit-flow-analytics-',
      );
      try {
        final result =
            await HabitHistoryExportService(
              dataSource: repository,
              now: () => clock,
              documentsDirectory: () async => exportRoot,
              shareFile: (_) async =>
                  const ShareResult('test', ShareResultStatus.success),
            ).export(
              HistoryExportRequest(
                startDate: DateTime(2026, 11, 2),
                endDate: DateTime(2026, 11, 6),
              ),
            );
        final workbook = Excel.decodeBytes(await result.file.readAsBytes());
        final summaryRows = workbook.tables['Summary']!.rows;
        int cellInt(List<Data?> row, int column) {
          final value = row[column]!.value;
          if (value is IntCellValue) return value.value;
          return int.parse(value.toString());
        }

        final workbookTotals = HabitPeriodCounts(
          scheduled: summaryRows
              .skip(1)
              .fold(0, (sum, row) => sum + cellInt(row, 2)),
          completed: summaryRows
              .skip(1)
              .fold(0, (sum, row) => sum + cellInt(row, 3)),
          missed: summaryRows
              .skip(1)
              .fold(0, (sum, row) => sum + cellInt(row, 4)),
        );
        expect(workbookTotals.scheduled, report.counts.scheduled);
        expect(workbookTotals.completed, report.counts.completed);
        expect(workbookTotals.missed, report.counts.missed);
        expect(workbookTotals.completionPercent, report.completionPercent);
      } finally {
        await exportRoot.delete(recursive: true);
      }
    },
  );

  test(
    'export supports a selected archived habit and rejects invalid range',
    () async {
      final habit = Habit(
        id: 'export-archived',
        name: 'Old reading habit',
        category: 'Learning',
        createdAt: DateTime(2026, 11, 1),
      );
      await repository.saveHabit(habit);
      clock = DateTime(2026, 11, 6, 12);
      await repository.setCompletion(
        habitId: habit.id,
        date: clock,
        status: CompletionStatus.completed,
      );
      clock = DateTime(2026, 11, 7, 9);
      await repository.archiveHabit(habit.id);
      final exportRoot = await Directory.systemTemp.createTemp(
        'habit-flow-xlsx-archived-',
      );
      try {
        final service = HabitHistoryExportService(
          dataSource: repository,
          now: () => clock,
          documentsDirectory: () async => exportRoot,
          shareFile: (_) async =>
              const ShareResult('test', ShareResultStatus.success),
        );
        final result = await service.export(
          HistoryExportRequest(
            habitId: habit.id,
            startDate: DateTime(2026, 11, 6),
            endDate: DateTime(2026, 11, 6),
          ),
        );
        expect(result.detailRowCount, 1);
        final workbook = Excel.decodeBytes(await result.file.readAsBytes());
        expect(workbook.tables['History']!.rows, hasLength(2));
        await expectLater(
          service.export(
            HistoryExportRequest(
              startDate: DateTime(2026, 11, 7),
              endDate: DateTime(2026, 11, 6),
            ),
          ),
          throwsArgumentError,
        );
      } finally {
        await exportRoot.delete(recursive: true);
      }
    },
  );

  test('export creates valid empty workbook when no habits exist', () async {
    final exportRoot = await Directory.systemTemp.createTemp(
      'habit-flow-xlsx-empty-',
    );
    try {
      final result = await HabitHistoryExportService(
        dataSource: repository,
        now: () => clock,
        documentsDirectory: () async => exportRoot,
        shareFile: (_) async =>
            const ShareResult('test', ShareResultStatus.success),
      ).export(const HistoryExportRequest());

      expect(result.detailRowCount, 0);
      expect(result.summaryRowCount, 0);
      final workbook = Excel.decodeBytes(await result.file.readAsBytes());
      expect(workbook.tables['History']!.rows, hasLength(1));
      expect(workbook.tables['Summary']!.rows, hasLength(1));
    } finally {
      await exportRoot.delete(recursive: true);
    }
  });

  test(
    'export marks unscheduled weekdays as No without adding missed rows',
    () async {
      final habit = Habit(
        id: 'export-weekdays',
        name: 'Walk',
        category: 'Health',
        scheduleType: HabitScheduleType.selectedWeekdays,
        selectedWeekdays: const [DateTime.monday],
        createdAt: DateTime(2026, 11, 1),
      );
      await repository.saveHabit(habit);
      final exportRoot = await Directory.systemTemp.createTemp(
        'habit-flow-xlsx-weekdays-',
      );
      try {
        final result =
            await HabitHistoryExportService(
              dataSource: repository,
              now: () => clock,
              documentsDirectory: () async => exportRoot,
              shareFile: (_) async =>
                  const ShareResult('test', ShareResultStatus.success),
            ).export(
              HistoryExportRequest(
                habitId: habit.id,
                startDate: DateTime(2026, 11, 1),
                endDate: DateTime(2026, 11, 2),
              ),
            );
        final workbook = Excel.decodeBytes(await result.file.readAsBytes());
        final rows = workbook.tables['History']!.rows;
        String text(int row, int column) {
          final cell = rows[row][column];
          if (cell == null) {
            throw StateError('Expected exported workbook cell.');
          }
          final value = cell.value;
          if (value is TextCellValue) return value.value.text ?? '';
          return value.toString();
        }

        expect(result.detailRowCount, 2);
        expect(text(1, 0), '2026-11-01');
        expect(text(1, 4), 'No');
        expect(text(1, 5), 'Unscheduled');
        expect(text(2, 0), '2026-11-02');
        expect(text(2, 4), 'Yes');
        expect(text(2, 5), 'Missed');
        expect(text(2, 6), '');
      } finally {
        await exportRoot.delete(recursive: true);
      }
    },
  );
}
