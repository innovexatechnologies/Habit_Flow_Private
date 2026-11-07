import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

enum HabitScheduleType { daily, selectedWeekdays, weeklyTarget }

enum HabitStatus { active, archived }

enum CompletionStatus { completed, missed }

class Habit {
  Habit({
    String? id,
    required this.name,
    this.description,
    required this.category,
    this.scheduleType = HabitScheduleType.daily,
    this.selectedWeekdays = const [],
    this.weeklyTarget,
    this.reminderEnabled = false,
    this.reminderTime,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.status = HabitStatus.active,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final String? description;
  final String category;
  final HabitScheduleType scheduleType;
  final List<int> selectedWeekdays;
  final int? weeklyTarget;
  final bool reminderEnabled;
  final String? reminderTime;
  final DateTime createdAt;
  final DateTime updatedAt;
  final HabitStatus status;

  Habit copyWith({
    String? name,
    String? description,
    bool clearDescription = false,
    String? category,
    HabitScheduleType? scheduleType,
    List<int>? selectedWeekdays,
    int? weeklyTarget,
    bool? reminderEnabled,
    String? reminderTime,
    DateTime? updatedAt,
    HabitStatus? status,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      description: clearDescription ? null : description ?? this.description,
      category: category ?? this.category,
      scheduleType: scheduleType ?? this.scheduleType,
      selectedWeekdays: selectedWeekdays ?? this.selectedWeekdays,
      weeklyTarget: weeklyTarget ?? this.weeklyTarget,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      status: status ?? this.status,
    );
  }
}

class HabitCompletion {
  HabitCompletion({
    String? id,
    required this.habitId,
    required this.localDate,
    required this.status,
    this.completedAt,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String habitId;
  final String localDate;
  final CompletionStatus status;
  final DateTime? completedAt;

  static String dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class HabitHistoryEntry {
  const HabitHistoryEntry({required this.completion, required this.habitName});

  final HabitCompletion completion;
  final String habitName;
}

class HabitHistorySummary {
  const HabitHistorySummary({
    required this.completedScheduledDays,
    required this.missedScheduledDays,
    required this.completionPercent,
  });

  final int completedScheduledDays;
  final int missedScheduledDays;
  final int completionPercent;
}

class HabitPreferences {
  const HabitPreferences({
    this.themeMode = ThemeMode.light,
    this.reminderDefaultEnabled = false,
    this.reminderDefaultTime = '09:00',
  });

  final ThemeMode themeMode;
  final bool reminderDefaultEnabled;
  final String reminderDefaultTime;

  HabitPreferences copyWith({
    ThemeMode? themeMode,
    bool? reminderDefaultEnabled,
    String? reminderDefaultTime,
  }) {
    return HabitPreferences(
      themeMode: themeMode ?? this.themeMode,
      reminderDefaultEnabled:
          reminderDefaultEnabled ?? this.reminderDefaultEnabled,
      reminderDefaultTime: reminderDefaultTime ?? this.reminderDefaultTime,
    );
  }
}
