import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:habit_flow/data/habit.dart';
import 'package:habit_flow/data/habit_controller.dart';
import 'package:habit_flow/data/habit_database.dart';
import 'package:habit_flow/data/local_habit_reminder_service.dart';
import 'package:habit_flow/main.dart';

void main() {
  testWidgets('bottom navigation opens all five destinations', (tester) async {
    await tester.pumpWidget(HabitFlowApp(dataSource: _FakeHabitDataSource()));
    await tester.pumpAndSettle();

    expect(find.textContaining('make today your own.'), findsOneWidget);

    await tester.tap(find.text('My Habits'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing on your list yet'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Your story starts here'), findsOneWidget);
    expect(find.text('Download History'), findsOneWidget);
    await tester.tap(find.text('Download History'));
    await tester.pumpAndSettle();
    expect(find.text('Complete history'), findsOneWidget);
    expect(find.text('Create workbook'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('SELECTED PERIOD'), findsOneWidget);
    expect(find.text('No scheduled check-ins yet'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await tester.tap(find.text('Date range'));
    await tester.pumpAndSettle();
    expect(find.textContaining('From '), findsOneWidget);
    expect(find.textContaining('To '), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Your privacy'), findsOneWidget);
  });

  testWidgets('empty screens remain scrollable without phone-width overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(HabitFlowApp(dataSource: _FakeHabitDataSource()));
    await tester.pumpAndSettle();
    for (final destination in [
      'My Habits',
      'History',
      'Analytics',
      'Settings',
    ]) {
      await tester.tap(find.text(destination));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$destination overflowed');
    }
  });

  testWidgets('populated screens remain usable at narrow phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = _FakeHabitDataSource();
    final habit = Habit(name: 'Daily reading', category: 'Learning');
    await source.saveHabit(habit);
    await source.setCompletion(
      habitId: habit.id,
      date: DateTime.now(),
      status: CompletionStatus.completed,
    );
    await tester.pumpWidget(HabitFlowApp(dataSource: source));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Home overflowed');

    for (final destination in [
      'My Habits',
      'History',
      'Analytics',
      'Settings',
    ]) {
      await tester.tap(find.text(destination));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$destination overflowed');
    }
  });

  testWidgets('a habit can be created, completed, and shown in history', (
    tester,
  ) async {
    await tester.pumpWidget(HabitFlowApp(dataSource: _FakeHabitDataSource()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add habit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Drink water');
    await tester.tap(find.text('Add habit').last);
    await tester.pumpAndSettle();

    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 of 1 scheduled habit · 1 left'), findsOneWidget);
    final habitName = find.text('Drink water');
    await tester.ensureVisible(habitName);
    await tester.tap(habitName);
    await tester.pumpAndSettle();
    expect(find.text('CURRENT STREAK'), findsOneWidget);
    await tester.tap(find.byTooltip('Close habit details'));
    await tester.pumpAndSettle();

    final completeButton = find.text('Complete');
    await tester.ensureVisible(completeButton);
    await tester.tap(completeButton);
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('1 day streak'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('1 of 1 scheduled habit · 0 left'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('0 day streak'), findsOneWidget);
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly completion trend'), findsOneWidget);
    expect(find.text('Monthly completion trend'), findsOneWidget);
    expect(find.byType(BarChart), findsNWidgets(2));
  });

  testWidgets('habit edits and archive preserve records and restore cleanly', (
    tester,
  ) async {
    final source = _FakeHabitDataSource();
    await tester.pumpWidget(HabitFlowApp(dataSource: source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add habit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Daily walk');
    await tester.tap(find.text('Add habit').last);
    await tester.pumpAndSettle();

    final habit = (await source.getHabits()).single;
    await source.setCompletion(
      habitId: habit.id,
      date: DateTime.now(),
      status: CompletionStatus.completed,
    );
    var habitOptions = find.byTooltip('Habit options');
    await tester.ensureVisible(habitOptions);
    await tester.tap(habitOptions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Evening walk');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect((await source.getHabits()).single.name, 'Evening walk');

    habitOptions = find.byTooltip('Habit options');
    await tester.ensureVisible(habitOptions);
    await tester.tap(habitOptions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();

    expect(await source.getHabits(), isEmpty);
    expect(await source.getCompletionsForHabit(habit.id), hasLength(1));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final restore = find.text('Restore');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();

    expect((await source.getHabits()).single.name, 'Evening walk');
    expect(await source.getCompletionsForHabit(habit.id), hasLength(1));
  });

  testWidgets('appearance setting changes the app theme mode', (tester) async {
    final source = _FakeHabitDataSource();
    await tester.pumpWidget(HabitFlowApp(dataSource: source));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect((await source.getPreferences()).themeMode, ThemeMode.dark);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect((await source.getPreferences()).themeMode, ThemeMode.system);
  });

  testWidgets('settings export shortcut opens history', (tester) async {
    await tester.pumpWidget(HabitFlowApp(dataSource: _FakeHabitDataSource()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final exportShortcut = find.text('Export history');
    await tester.ensureVisible(exportShortcut);
    await tester.tap(exportShortcut);
    await tester.pumpAndSettle();
    expect(find.text('Download History'), findsOneWidget);
  });

  testWidgets('reminder defaults are saved from Settings', (tester) async {
    final source = _FakeHabitDataSource();
    await tester.pumpWidget(HabitFlowApp(dataSource: source));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final reminderDefault = find.text('Default reminder for new habits');
    await tester.ensureVisible(reminderDefault);
    await tester.tap(reminderDefault);
    await tester.pumpAndSettle();
    expect((await source.getPreferences()).reminderDefaultEnabled, isTrue);
    expect(find.text('Default time: 09:00'), findsOneWidget);

    final reminderTime = find.text('Default reminder time');
    await tester.ensureVisible(reminderTime);
    await tester.tap(reminderTime);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((await source.getPreferences()).reminderDefaultTime, '09:00');
  });

  testWidgets('archived habits can be restored without losing history', (
    tester,
  ) async {
    final source = _FakeHabitDataSource();
    final habit = Habit(name: 'Read', category: 'Learning');
    await source.saveHabit(habit);
    await source.setCompletion(
      habitId: habit.id,
      date: DateTime.now(),
      status: CompletionStatus.completed,
    );
    await source.archiveHabit(habit.id);

    await tester.pumpWidget(HabitFlowApp(dataSource: source));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Read'), findsOneWidget);
    final restore = find.text('Restore');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await tester.pumpAndSettle();

    expect(
      (await source.getHabits()).map((item) => item.id),
      contains(habit.id),
    );
    expect(await source.getCompletionsForHabit(habit.id), hasLength(1));
    expect(find.text('Restore'), findsNothing);
  });

  testWidgets('clear all requires typing CLEAR and resets only after confirm', (
    tester,
  ) async {
    final source = _FakeHabitDataSource();
    final habit = Habit(name: 'Walk', category: 'Health');
    await source.saveHabit(habit);
    await source.setCompletion(
      habitId: habit.id,
      date: DateTime.now(),
      status: CompletionStatus.completed,
    );

    await tester.pumpWidget(HabitFlowApp(dataSource: source));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    final clearAction = find.text('Clear all local data');
    await tester.ensureVisible(clearAction);
    await tester.tap(clearAction);
    await tester.pumpAndSettle();

    final clearButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Clear everything'),
    );
    expect(clearButton.onPressed, isNull);
    expect(await source.getHabits(), hasLength(1));

    await tester.enterText(find.byType(TextField).last, 'CLEAR');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear everything'));
    await tester.pumpAndSettle();

    expect(await source.getHabits(includeArchived: true), isEmpty);
    expect(await source.getCompletionsForHabit(habit.id), isEmpty);
    expect((await source.getPreferences()).themeMode, ThemeMode.light);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });

  test(
    'local reminders reschedule, disable, cancel, and restore on restart',
    () async {
      final source = _FakeHabitDataSource();
      final firstService = _FakeHabitReminderService();
      final controller = HabitController(source, reminderService: firstService);
      await controller.initialize();
      final habit = Habit(
        id: 'reminder-habit',
        name: 'Evening walk',
        category: 'Health',
        reminderEnabled: true,
        reminderTime: '18:30',
      );

      expect(await controller.saveHabit(habit), ReminderSyncStatus.scheduled);
      expect(firstService.scheduled[habit.id], '18:30');

      final restartService = _FakeHabitReminderService();
      final restartedController = HabitController(
        source,
        reminderService: restartService,
      );
      await restartedController.initialize();
      expect(restartService.scheduled[habit.id], '18:30');

      final updated = habit.copyWith(reminderTime: '19:15');
      expect(
        await restartedController.saveHabit(updated),
        ReminderSyncStatus.scheduled,
      );
      expect(restartService.scheduled[habit.id], '19:15');

      final disabled = updated.copyWith(reminderEnabled: false);
      expect(
        await restartedController.saveHabit(disabled),
        ReminderSyncStatus.disabled,
      );
      expect(restartService.scheduled.containsKey(habit.id), isFalse);

      await restartedController.saveHabit(updated);
      await restartedController.archiveHabit(habit.id);
      expect(restartService.scheduled.containsKey(habit.id), isFalse);
      expect(restartService.cancelled, contains(habit.id));
    },
  );

  test(
    'notification permission denial is handled without scheduling',
    () async {
      final source = _FakeHabitDataSource();
      final reminderService = _FakeHabitReminderService(
        permissionGranted: false,
      );
      final controller = HabitController(
        source,
        reminderService: reminderService,
      );
      await controller.initialize();
      final habit = Habit(
        id: 'permission-denied-habit',
        name: 'Journal',
        category: 'Mindfulness',
        reminderEnabled: true,
        reminderTime: '20:00',
      );

      expect(
        await controller.saveHabit(habit),
        ReminderSyncStatus.permissionDenied,
      );
      expect(await controller.requestNotificationsPermission(), isFalse);
      expect(reminderService.permissionRequests, 1);
      expect(reminderService.scheduled, isEmpty);
      expect(controller.activeHabits.single.reminderEnabled, isTrue);
    },
  );
}

class _FakeHabitReminderService implements HabitReminderService {
  _FakeHabitReminderService({this.permissionGranted = true});

  final bool permissionGranted;
  final Map<String, String> scheduled = {};
  final List<String> cancelled = [];
  int permissionRequests = 0;
  bool initialized = false;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<bool> areNotificationsEnabled() async => permissionGranted;

  @override
  Future<bool> requestNotificationsPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<ReminderSyncStatus> syncHabit(Habit habit) async {
    await cancelHabit(habit.id);
    if (!habit.reminderEnabled || habit.status == HabitStatus.archived) {
      return ReminderSyncStatus.disabled;
    }
    if (!permissionGranted) return ReminderSyncStatus.permissionDenied;
    scheduled[habit.id] = habit.reminderTime!;
    return ReminderSyncStatus.scheduled;
  }

  @override
  Future<void> cancelHabit(String habitId) async {
    cancelled.add(habitId);
    scheduled.remove(habitId);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }

  @override
  Future<void> openNotificationSettings() async {}
}

class _FakeHabitDataSource implements HabitDataSource {
  _FakeHabitDataSource();

  final List<Habit> _habits = [];
  final List<HabitCompletion> _completions = [];
  HabitPreferences _preferences = const HabitPreferences();

  @override
  Future<List<Habit>> getHabits({bool includeArchived = false}) async => _habits
      .where((habit) => includeArchived || habit.status == HabitStatus.active)
      .toList();

  @override
  Future<List<HabitCompletion>> getCompletionsForDate(DateTime date) async =>
      _completions
          .where(
            (completion) =>
                completion.localDate == HabitCompletion.dateKey(date),
          )
          .toList();

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(String habitId) async =>
      _completions
          .where((completion) => completion.habitId == habitId)
          .toList();

  @override
  Future<Map<String, List<HabitCompletion>>> getCompletionsForHabits(
    List<String> habitIds,
  ) async => {
    for (final habitId in habitIds)
      habitId: await getCompletionsForHabit(habitId),
  };

  @override
  Future<List<HabitHistoryEntry>> getRecentHistory({int limit = 100}) async {
    final entries =
        _completions.map((completion) {
          final habit = _habits.firstWhere(
            (item) => item.id == completion.habitId,
          );
          return HabitHistoryEntry(
            completion: completion,
            habitName: habit.name,
          );
        }).toList()..sort(
          (a, b) => b.completion.localDate.compareTo(a.completion.localDate),
        );
    return entries.take(limit).toList();
  }

  @override
  Future<List<HabitHistoryEntry>> getAllHistory() =>
      getRecentHistory(limit: _completions.length);

  @override
  Future<void> saveHabit(Habit habit) async {
    _habits.removeWhere((item) => item.id == habit.id);
    _habits.add(habit);
  }

  @override
  Future<void> archiveHabit(String id) async {
    final index = _habits.indexWhere((habit) => habit.id == id);
    _habits[index] = _habits[index].copyWith(status: HabitStatus.archived);
  }

  @override
  Future<void> setCompletion({
    required String habitId,
    required DateTime date,
    required CompletionStatus status,
  }) async {
    if (status != CompletionStatus.completed) {
      throw ArgumentError('Only completed check-ins can be saved directly.');
    }
    final localDate = HabitCompletion.dateKey(date);
    final existingIndex = _completions.indexWhere(
      (item) => item.habitId == habitId && item.localDate == localDate,
    );
    final existing = existingIndex < 0
        ? null
        : _completions.removeAt(existingIndex);
    _completions.add(
      HabitCompletion(
        id: existing?.id,
        habitId: habitId,
        localDate: localDate,
        status: status,
        completedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> undoCompletion({
    required String habitId,
    required DateTime date,
  }) async {
    final key = HabitCompletion.dateKey(date);
    _completions.removeWhere(
      (item) => item.habitId == habitId && item.localDate == key,
    );
  }

  @override
  Future<HabitPreferences> getPreferences() async => _preferences;

  @override
  Future<void> savePreferences(HabitPreferences preferences) async {
    _preferences = preferences;
  }

  @override
  Future<void> clearAllData() async {
    _habits.clear();
    _completions.clear();
    _preferences = const HabitPreferences();
  }
}
