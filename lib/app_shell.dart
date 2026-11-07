import 'dart:async';

import 'package:flutter/material.dart';

import 'app_widgets.dart';
import 'data/habit.dart';
import 'data/habit_controller.dart';
import 'data/local_habit_reminder_service.dart';
import 'data/habit_schedule.dart';
import 'pages/analytics_page.dart';
import 'pages/app_pages.dart';

class HabitFlowShell extends StatefulWidget {
  const HabitFlowShell({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final HabitController controller;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;

  @override
  State<HabitFlowShell> createState() => _HabitFlowShellState();
}

class _HabitFlowShellState extends State<HabitFlowShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  Timer? _midnightRefresh;

  static const _destinations = [
    _Destination('Home', Icons.home_outlined, Icons.home_rounded),
    _Destination('My Habits', Icons.check_circle_outline, Icons.check_circle),
    _Destination(
      'History',
      Icons.calendar_month_outlined,
      Icons.calendar_month,
    ),
    _Destination('Analytics', Icons.insights_outlined, Icons.insights_rounded),
    _Destination('Settings', Icons.tune_rounded, Icons.tune_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showReminderPermissionWarningIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightRefresh?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshOnResume();
    _scheduleMidnightRefresh();
  }

  Future<void> _refreshOnResume() async {
    try {
      await widget.controller.refresh();
      await widget.controller.rescheduleReminders();
      await _showReminderPermissionWarningIfNeeded();
    } catch (error) {
      _showError('Could not refresh HabitFlow data and reminders: $error');
    }
  }

  Future<void> _showReminderPermissionWarningIfNeeded() async {
    if (!mounted || !widget.controller.supportsLocalReminders) return;
    final reminderError = widget.controller.reminderInitializationError;
    if (reminderError != null) {
      _showError('Could not initialize local habit reminders: $reminderError');
      return;
    }
    final hasEnabledReminder = widget.controller.activeHabits.any(
      (habit) => habit.reminderEnabled,
    );
    if (!hasEnabledReminder) return;
    try {
      if (!await widget.controller.areNotificationsEnabled()) {
        _showReminderPermissionDenied();
      }
    } catch (error) {
      _showError('Could not check notification permission: $error');
    }
  }

  void _scheduleMidnightRefresh() {
    _midnightRefresh?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnightRefresh = Timer(nextDay.difference(now), () {
      widget.controller
          .refresh()
          .then((_) {
            if (mounted) _scheduleMidnightRefresh();
          })
          .catchError((Object error) {
            _showError('Could not refresh today’s habit check-ins: $error');
            if (mounted) _scheduleMidnightRefresh();
          });
    });
  }

  Future<void> _editHabit([Habit? habit]) async {
    final result = await showDialog<Habit>(
      context: context,
      builder: (context) => _HabitEditorDialog(
        habit: habit,
        reminderDefaultEnabled:
            widget.controller.preferences.reminderDefaultEnabled,
        reminderDefaultTime: widget.controller.preferences.reminderDefaultTime,
      ),
    );
    if (result == null || !mounted) return;
    var reminderDeclined = false;
    var habitToSave = result;
    try {
      if (result.reminderEnabled &&
          (habit == null || !habit.reminderEnabled) &&
          widget.controller.supportsLocalReminders) {
        final enabled = await widget.controller.areNotificationsEnabled();
        if (!enabled) {
          final explain = await _explainReminderPermission();
          if (!mounted) return;
          if (!explain) {
            habitToSave = result.copyWith(reminderEnabled: false);
            reminderDeclined = true;
          } else if (!await widget.controller
              .requestNotificationsPermission()) {
            reminderDeclined = true;
          }
        }
      }
      final status = await widget.controller.saveHabit(habitToSave);
      if (reminderDeclined) {
        _showReminderPermissionDenied();
      } else {
        switch (status) {
          case ReminderSyncStatus.scheduled:
          case ReminderSyncStatus.disabled:
            break;
          case ReminderSyncStatus.permissionDenied:
            _showReminderPermissionDenied();
            break;
          case ReminderSyncStatus.unsupported:
            _showError(
              'This device does not support local habit notifications.',
            );
        }
      }
    } on HabitReminderSyncException catch (error) {
      _showError(error.toString());
    } catch (error) {
      _showError('Could not save habit: $error');
    }
  }

  Future<bool> _explainReminderPermission() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.notifications_active_outlined),
            title: const Text('Allow habit reminders?'),
            content: const Text(
              'HabitFlow can send an optional notification at the time you '
              'selected. Reminders are scheduled on this device and work '
              'offline. Android notification permission is needed to show them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _setCompletion(String habitId, bool completed) async {
    try {
      await widget.controller.setCompleted(habitId, completed);
    } catch (error) {
      _showError('Could not update today’s check-in: $error');
    }
  }

  Future<void> _archiveHabit(Habit habit) async {
    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive this habit?'),
        content: Text(
          '“${habit.name}” will leave your active list. Its completion history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (shouldArchive != true || !mounted) return;
    try {
      await widget.controller.archiveHabit(habit.id);
    } on HabitReminderSyncException catch (error) {
      _showError(error.toString());
    } catch (error) {
      _showError('Could not archive habit: $error');
    }
  }

  void _showReminderPermissionDenied() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'Habit reminder saved, but Android notifications are off. '
            'Allow them in system settings to receive alerts.',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () async {
              try {
                await widget.controller.openNotificationSettings();
              } catch (error) {
                _showError('Could not open notification settings: $error');
              }
            },
          ),
        ),
      );
  }

  Future<void> _viewHabit(Habit habit) async {
    final theme = Theme.of(context);
    final history =
        widget.controller.allCompletionsByHabit[habit.id] ?? const [];
    final streak =
        widget.controller.allStreaks[habit.id] ??
        const HabitStreaks(current: 0, longest: 0);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: HabitHistoryDetail(
            habit: habit,
            completions: history,
            streak: streak,
            asOf: DateTime.now(),
            onEdit: () {
              Navigator.pop(context);
              _editHabit(habit);
            },
            onClose: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showAddAction = _selectedIndex == 0 || _selectedIndex == 1;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            const HabitFlowMark(size: 38),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'HabitFlow',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.45,
                  ),
                ),
                Text(
                  'ONE DAY AT A TIME',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    letterSpacing: 1.15,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About HabitFlow',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => const AppMessageDialog(
                  icon: Icons.waves_rounded,
                  title: 'Build your rhythm',
                  message:
                      'HabitFlow is a personal habit tracker foundation, '
                      'designed to work offline.',
                  confirmLabel: 'Sounds good',
                ),
              );
            },
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            HomePage(
              controller: widget.controller,
              onAddHabit: _editHabit,
              onToggleCompletion: _setCompletion,
              onEditHabit: _editHabit,
              onArchiveHabit: _archiveHabit,
              onViewHabit: _viewHabit,
            ),
            MyHabitsPage(
              controller: widget.controller,
              onAddHabit: _editHabit,
              onToggleCompletion: _setCompletion,
              onEditHabit: _editHabit,
              onArchiveHabit: _archiveHabit,
              onViewHabit: _viewHabit,
            ),
            HistoryPage(controller: widget.controller, onViewHabit: _viewHabit),
            AnalyticsPage(controller: widget.controller),
            SettingsPage(
              controller: widget.controller,
              themeMode: widget.themeMode,
              onThemeModeChanged: widget.onThemeModeChanged,
              onOpenHistory: () => setState(() => _selectedIndex = 2),
              onError: _showError,
            ),
          ],
        ),
      ),
      floatingActionButton: showAddAction
          ? FloatingActionButton.extended(
              onPressed: _editHabit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add habit'),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.65),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: [
            for (var index = 0; index < _destinations.length; index++)
              NavigationDestination(
                icon: Icon(_destinations[index].icon),
                selectedIcon: Icon(_destinations[index].selectedIcon),
                label: _destinations[index].label,
              ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _HabitEditorDialog extends StatefulWidget {
  const _HabitEditorDialog({
    required this.habit,
    required this.reminderDefaultEnabled,
    required this.reminderDefaultTime,
  });

  final Habit? habit;
  final bool reminderDefaultEnabled;
  final String reminderDefaultTime;

  @override
  State<_HabitEditorDialog> createState() => _HabitEditorDialogState();
}

class _HabitEditorDialogState extends State<_HabitEditorDialog> {
  static const _categories = [
    'Health',
    'Mindfulness',
    'Learning',
    'Productivity',
    'Other',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _category;
  late HabitScheduleType _scheduleType;
  late Set<int> _selectedWeekdays;
  late int _weeklyTarget;
  late bool _reminderEnabled;
  late String _reminderTime;

  @override
  void initState() {
    super.initState();
    final habit = widget.habit;
    _nameController = TextEditingController(text: habit?.name ?? '');
    _descriptionController = TextEditingController(
      text: habit?.description ?? '',
    );
    _category = habit?.category ?? _categories.first;
    _scheduleType = habit?.scheduleType ?? HabitScheduleType.daily;
    _selectedWeekdays = habit?.selectedWeekdays.toSet() ?? {};
    _weeklyTarget = habit?.weeklyTarget ?? 3;
    _reminderEnabled = habit?.reminderEnabled ?? widget.reminderDefaultEnabled;
    _reminderTime = habit?.reminderTime ?? widget.reminderDefaultTime;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.habit == null ? 'Add a habit' : 'Edit habit'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Habit name',
                    hintText: 'e.g. Take a short walk',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a habit name'
                      : null,
                ),
                TextFormField(
                  controller: _descriptionController,
                  maxLength: 180,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final category in _categories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 18),
                Text('SCHEDULE', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<HabitScheduleType>(
                  initialValue: _scheduleType,
                  decoration: const InputDecoration(
                    labelText: 'Repeat',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: HabitScheduleType.daily,
                      child: Text('Every day'),
                    ),
                    DropdownMenuItem(
                      value: HabitScheduleType.selectedWeekdays,
                      child: Text('Selected weekdays'),
                    ),
                    DropdownMenuItem(
                      value: HabitScheduleType.weeklyTarget,
                      child: Text('Weekly target'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _scheduleType = value);
                  },
                ),
                if (_scheduleType == HabitScheduleType.selectedWeekdays) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var day = 1; day <= _weekdays.length; day++)
                        FilterChip(
                          label: Text(_weekdays[day - 1]),
                          selected: _selectedWeekdays.contains(day),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedWeekdays.add(day);
                              } else {
                                _selectedWeekdays.remove(day);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ],
                if (_scheduleType == HabitScheduleType.weeklyTarget)
                  DropdownButtonFormField<int>(
                    initialValue: _weeklyTarget,
                    decoration: const InputDecoration(
                      labelText: 'Times per week',
                    ),
                    items: [
                      for (var target = 1; target <= 7; target++)
                        DropdownMenuItem(
                          value: target,
                          child: Text(
                            '$target ${target == 1 ? 'time' : 'times'} a week',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _weeklyTarget = value);
                    },
                  ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reminder'),
                  subtitle: Text('At $_reminderTime'),
                  value: _reminderEnabled,
                  onChanged: (value) async {
                    if (value && !await _chooseReminderTime()) return;
                    if (mounted) setState(() => _reminderEnabled = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.habit == null ? 'Add habit' : 'Save changes'),
        ),
      ],
    );
  }

  Future<bool> _chooseReminderTime() async {
    final parts = _reminderTime.split(':').map(int.parse).toList();
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
    );
    if (selected == null || !mounted) return false;
    setState(() {
      _reminderTime =
          '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    });
    return true;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_scheduleType == HabitScheduleType.selectedWeekdays &&
        _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one weekday.')),
      );
      return;
    }
    final previous = widget.habit;
    final now = DateTime.now();
    Navigator.pop(
      context,
      Habit(
        id: previous?.id,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        scheduleType: _scheduleType,
        selectedWeekdays: _scheduleType == HabitScheduleType.selectedWeekdays
            ? (_selectedWeekdays.toList()..sort())
            : const [],
        weeklyTarget: _scheduleType == HabitScheduleType.weeklyTarget
            ? _weeklyTarget
            : null,
        reminderEnabled: _reminderEnabled,
        reminderTime: _reminderEnabled ? _reminderTime : null,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
        status: previous?.status ?? HabitStatus.active,
      ),
    );
  }
}
