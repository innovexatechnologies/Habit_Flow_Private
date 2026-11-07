import 'package:flutter/material.dart';

import 'habit.dart';
import 'habit_database.dart';
import 'local_habit_reminder_service.dart';
import 'habit_schedule.dart';

class HabitController extends ChangeNotifier {
  HabitController(this.repository, {this.reminderService});

  final HabitDataSource repository;
  final HabitReminderService? reminderService;

  List<Habit> activeHabits = const [];
  List<Habit> allHabits = const [];
  List<HabitCompletion> todayCompletions = const [];
  List<HabitHistoryEntry> history = const [];
  List<HabitHistoryEntry> allHistory = const [];
  Map<String, HabitStreaks> streaks = const {};
  Map<String, HabitStreaks> allStreaks = const {};
  Map<String, List<HabitCompletion>> completionsByHabit = const {};
  Map<String, List<HabitCompletion>> allCompletionsByHabit = const {};
  TodayHabitSummary todaySummary = const TodayHabitSummary(
    activeCount: 0,
    scheduledHabits: [],
    completedCount: 0,
    overallStreak: 0,
  );
  HabitPreferences preferences = const HabitPreferences();
  bool get supportsLocalReminders => reminderService != null;
  Object? reminderInitializationError;

  Future<void> initialize() async {
    preferences = await repository.getPreferences();
    await refresh();
    final reminders = reminderService;
    if (reminders == null) return;
    try {
      await reminders.initialize();
      await rescheduleReminders();
      reminderInitializationError = null;
    } catch (error) {
      reminderInitializationError = error;
    }
  }

  Future<void> refresh() async {
    allHabits = await repository.getHabits(includeArchived: true);
    activeHabits = allHabits
        .where((habit) => habit.status == HabitStatus.active)
        .toList(growable: false);
    todayCompletions = await repository.getCompletionsForDate(DateTime.now());
    allHistory = await repository.getAllHistory();
    history = allHistory.take(100).toList(growable: false);
    allCompletionsByHabit = await repository.getCompletionsForHabits(
      allHabits.map((habit) => habit.id).toList(growable: false),
    );
    completionsByHabit = {
      for (final habit in activeHabits)
        habit.id: allCompletionsByHabit[habit.id] ?? const [],
    };
    final now = DateTime.now();
    allStreaks = {
      for (final habit in allHabits)
        habit.id: HabitSchedule.calculateStreaks(
          habit: habit,
          completions: allCompletionsByHabit[habit.id] ?? const [],
          asOf: habit.status == HabitStatus.archived &&
                  habit.updatedAt.isBefore(now)
              ? habit.updatedAt
              : now,
        ),
    };
    streaks = {
      for (final habit in activeHabits) habit.id: allStreaks[habit.id]!,
    };
    todaySummary = HabitSchedule.summarizeToday(
        activeHabits: activeHabits,
        completionsByHabit: completionsByHabit,
        todayCompletions: todayCompletions,
        asOf: now,
    );
    notifyListeners();
  }

  Future<ReminderSyncStatus> saveHabit(Habit habit) async {
    await repository.saveHabit(habit);
    await refresh();
    final reminders = reminderService;
    if (reminders == null) return ReminderSyncStatus.unsupported;
    try {
      return await reminders.syncHabit(habit);
    } catch (error) {
      throw HabitReminderSyncException(habit.name, error);
    }
  }

  Future<void> archiveHabit(String id) async {
    final habit = allHabits.where((item) => item.id == id).firstOrNull;
    await repository.archiveHabit(id);
    await refresh();
    if (habit == null || reminderService == null) return;
    try {
      await reminderService!.cancelHabit(id);
    } catch (error) {
      throw HabitReminderSyncException(habit.name, error);
    }
  }

  Future<ReminderSyncStatus> restoreArchivedHabit(String id) async {
    final habit = allHabits.where((item) => item.id == id).firstOrNull;
    if (habit == null || habit.status != HabitStatus.archived) {
      throw StateError('The archived habit was not found.');
    }
    return saveHabit(habit.copyWith(status: HabitStatus.active));
  }

  Future<bool> areNotificationsEnabled() async =>
      await reminderService?.areNotificationsEnabled() ?? false;

  Future<bool> requestNotificationsPermission() async =>
      await reminderService?.requestNotificationsPermission() ?? false;

  Future<void> rescheduleReminders() async {
    final reminders = reminderService;
    if (reminders == null) return;
    for (final habit in allHabits) {
      try {
        await reminders.syncHabit(habit);
      } catch (error) {
        throw HabitReminderSyncException(habit.name, error);
      }
    }
  }

  Future<void> openNotificationSettings() async {
    final reminders = reminderService;
    if (reminders is LocalHabitReminderService) {
      await reminders.openNotificationSettings();
    }
  }

  Future<void> setCompleted(String habitId, bool completed) async {
    if (completed) {
      await repository.setCompletion(
        habitId: habitId,
        date: DateTime.now(),
        status: CompletionStatus.completed,
      );
    } else {
      await repository.undoCompletion(
        habitId: habitId,
        date: DateTime.now(),
      );
    }
    await refresh();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final updated = preferences.copyWith(themeMode: mode);
    await updatePreferences(updated);
  }

  Future<void> updatePreferences(HabitPreferences updated) async {
    await repository.savePreferences(updated);
    preferences = updated;
    notifyListeners();
  }

  Future<void> clearAllData() async {
    final reminders = reminderService;
    if (reminders != null) await reminders.cancelAll();
    await repository.clearAllData();
    preferences = const HabitPreferences();
    await refresh();
  }
}
