import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'habit.dart';

enum ReminderSyncStatus { scheduled, disabled, permissionDenied, unsupported }

abstract interface class HabitReminderService {
  Future<void> initialize();
  Future<bool> areNotificationsEnabled();
  Future<bool> requestNotificationsPermission();
  Future<ReminderSyncStatus> syncHabit(Habit habit);
  Future<void> cancelHabit(String habitId);
  Future<void> cancelAll();
  Future<void> openNotificationSettings();
}

class HabitReminderSyncException implements Exception {
  const HabitReminderSyncException(this.habitName, this.cause);

  final String habitName;
  final Object cause;

  @override
  String toString() =>
      '“$habitName” was saved, but its reminder could not be updated: $cause';
}

class LocalHabitReminderService implements HabitReminderService {
  LocalHabitReminderService({
    FlutterLocalNotificationsPlugin? notifications,
    DateTime Function()? now,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _now = now ?? DateTime.now;

  static const _weekdayCount = 7;
  static const _channelId = 'habit_reminders';

  final FlutterLocalNotificationsPlugin _notifications;
  final DateTime Function() _now;
  tz.Location? _location;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      _location = tz.getLocation(timezone.identifier);
    } catch (error) {
      debugPrint('Habit reminder timezone setup failed: $error');
      _location ??= tz.local;
    }
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    final android = _androidPlugin;
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          'Habit reminders',
          description:
              'Optional reminders for habits you choose to be notified about.',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        ),
      );
    }
    _initialized = true;
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    final android = _androidPlugin;
    if (android == null) return false;
    return await android.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestNotificationsPermission() async {
    final android = _androidPlugin;
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<ReminderSyncStatus> syncHabit(Habit habit) async {
    await initialize();
    await cancelHabit(habit.id);
    if (habit.status != HabitStatus.active || !habit.reminderEnabled) {
      return ReminderSyncStatus.disabled;
    }
    if (!await areNotificationsEnabled()) {
      return ReminderSyncStatus.permissionDenied;
    }
    final location = _location;
    if (location == null) return ReminderSyncStatus.unsupported;

    final time = _parseTime(habit.reminderTime);
    final weekdays = switch (habit.scheduleType) {
      HabitScheduleType.daily => List<int>.generate(7, (index) => index + 1),
      HabitScheduleType.selectedWeekdays => habit.selectedWeekdays,
      HabitScheduleType.weeklyTarget => List<int>.generate(
        7,
        (index) => index + 1,
      ),
    };
    if (weekdays.isEmpty) return ReminderSyncStatus.disabled;

    for (final weekday in weekdays.toSet()) {
      final scheduledDate = _nextOccurrence(
        location: location,
        weekday: weekday,
        hour: time.$1,
        minute: time.$2,
      );
      await _notifications.zonedSchedule(
        id: _notificationId(habit.id, weekday),
        title: 'Time for your habit!',
        body:
            'It’s time to complete your ${habit.name}. Stay consistent and keep your streak alive!',
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Habit reminders',
            channelDescription: 'Optional reminders for habits you choose to be notified about.',
            importance: Importance.max,
            priority: Priority.max,
            enableVibration: true,
            playSound: true,
            visibility: NotificationVisibility.public,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'habit:${habit.id}',
      );
    }
    return ReminderSyncStatus.scheduled;
  }

  @override
  Future<void> cancelHabit(String habitId) async {
    for (var weekday = 1; weekday <= _weekdayCount; weekday++) {
      await _notifications.cancel(id: _notificationId(habitId, weekday));
    }
  }

  @override
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  @override
  Future<void> openNotificationSettings() async {
    final android = _androidPlugin;
    if (android == null) return;
    await android.openAppNotificationSettings();
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    return _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
  }

  (int, int) _parseTime(String? time) {
    if (time == null) throw const FormatException('Reminder time is missing.');
    final parts = time.split(':');
    if (parts.length != 2)
      throw FormatException('Invalid reminder time: $time');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || hour < 0 || hour > 23) {
      throw FormatException('Invalid reminder hour: $time');
    }
    if (minute == null || minute < 0 || minute > 59) {
      throw FormatException('Invalid reminder minute: $time');
    }
    return (hour, minute);
  }

  tz.TZDateTime _nextOccurrence({
    required tz.Location location,
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final now = tz.TZDateTime.from(_now(), location);
    var daysUntil = (weekday - now.weekday) % 7;
    var scheduled = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day + daysUntil,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      daysUntil += 7;
      scheduled = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day + daysUntil,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  static int _notificationId(String habitId, int weekday) {
    var hash = 0x811c9dc5;
    for (final codeUnit in habitId.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0x0fffffff;
    }
    return hash * 8 + weekday;
  }
}
