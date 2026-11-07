import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../app_widgets.dart';
import '../data/habit.dart';
import '../data/habit_controller.dart';
import '../data/history_export_service.dart';
import '../data/habit_schedule.dart';
import '../data/local_habit_reminder_service.dart';

typedef HabitAction = Future<void> Function(Habit habit);
typedef CompletionAction = Future<void> Function(
  String habitId,
  bool completed,
);

class HomePage extends StatelessWidget {
  const HomePage({
    required this.controller,
    required this.onAddHabit,
    required this.onToggleCompletion,
    required this.onEditHabit,
    required this.onArchiveHabit,
    required this.onViewHabit,
    super.key,
  });

  final HabitController controller;
  final VoidCallback onAddHabit;
  final CompletionAction onToggleCompletion;
  final HabitAction onEditHabit;
  final HabitAction onArchiveHabit;
  final HabitAction onViewHabit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final completedIds = controller.todayCompletions
        .where((completion) => completion.status == CompletionStatus.completed)
        .map((completion) => completion.habitId)
        .toSet();
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final summary = controller.todaySummary;
    final total = summary.scheduledCount;
    final completed = summary.completedCount;
    final remaining = summary.remainingCount;
    const greeting = 'Have a good day.';

    return AppPage(
      children: [
        Text(
          '${weekdays[now.weekday - 1]}  ·  ${months[now.month - 1]} ${now.day}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(greeting, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          'Build consistency, one day at a time.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _CountBadge(
              icon: Icons.track_changes_rounded,
              value: '${summary.activeCount}',
              label: 'ACTIVE',
            ),
            const SizedBox(width: 8),
            _CountBadge(
              icon: Icons.check_rounded,
              value: '$completed',
              label: 'DONE',
            ),
            const SizedBox(width: 8),
            _CountBadge(
              icon: Icons.hourglass_bottom_rounded,
              value: '$remaining',
              label: 'LEFT',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _WelcomeCard(
          completed: completed,
          total: total,
          percentage: summary.completionPercent,
          overallStreak: summary.overallStreak,
          onAddHabit: onAddHabit,
        ),
        const SizedBox(height: 28),
        SectionHeading(
          title: 'Today',
          subtitle: total == 0
              ? 'Make space for the habits you want to grow.'
              : '$completed of $total scheduled ${total == 1 ? 'habit' : 'habits'} · $remaining left',
        ),
        const SizedBox(height: 14),
        if (summary.scheduledCount == 0)
          const AppEmptyState(
            icon: Icons.spa_outlined,
            title: 'Nothing scheduled today',
            message: 'Enjoy a little breathing room. Your next scheduled habits will show up here.',
          )
        else
          for (final habit in summary.scheduledHabits) ...[
            _HabitCard(
              habit: habit,
              completed: completedIds.contains(habit.id),
              streak:
                  controller.streaks[habit.id] ??
                  const HabitStreaks(current: 0, longest: 0),
              completions: controller.completionsByHabit[habit.id] ?? const [],
              onToggleCompletion: onToggleCompletion,
              onEdit: onEditHabit,
              onArchive: onArchiveHabit,
              onView: onViewHabit,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.completed,
    required this.total,
    required this.percentage,
    required this.overallStreak,
    required this.onAddHabit,
  });

  final int completed;
  final int total;
  final int percentage;
  final int overallStreak;
  final VoidCallback onAddHabit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardStart = isDark
        ? const Color(0xFF294538)
        : const Color(0xFF1E493B);
    final cardEnd = isDark ? const Color(0xFF20372D) : const Color(0xFF32634F);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cardStart, cardEnd],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cardStart.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? 'Start with one small step'
                      : 'Your daily rhythm',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _ProgressRing(
                completed: completed,
                total: total,
                percentage: percentage,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            total == 0
                ? 'A steady rhythm begins with a single intention.'
                : completed == total
                ? 'You showed up for every habit today.'
                : '$overallStreak day consistency streak · every small check-in counts.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          if (total == 0) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAddHabit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create your first habit'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E493B),
                minimumSize: const Size(48, 46),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.completed,
    required this.total,
    required this.percentage,
  });

  final int completed;
  final int total;
  final int percentage;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 54,
            height: 54,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          Text(
            total == 0 ? '—' : '$percentage%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class MyHabitsPage extends StatelessWidget {
  const MyHabitsPage({
    required this.controller,
    required this.onAddHabit,
    required this.onToggleCompletion,
    required this.onEditHabit,
    required this.onArchiveHabit,
    required this.onViewHabit,
    super.key,
  });

  final HabitController controller;
  final VoidCallback onAddHabit;
  final CompletionAction onToggleCompletion;
  final HabitAction onEditHabit;
  final HabitAction onArchiveHabit;
  final HabitAction onViewHabit;

  @override
  Widget build(BuildContext context) {
    final completedIds = controller.todayCompletions
        .where((completion) => completion.status == CompletionStatus.completed)
        .map((completion) => completion.habitId)
        .toSet();
    return AppPage(
      children: [
        SectionHeading(
          title: 'My Habits',
          subtitle:
              '${controller.activeHabits.length} active ${controller.activeHabits.length == 1 ? 'habit' : 'habits'} · small steps add up to meaningful change.',
        ),
        const SizedBox(height: 18),
        if (controller.activeHabits.isEmpty) ...[
          const AppEmptyState(
            icon: Icons.checklist_rounded,
            title: 'Nothing on your list yet',
            message: 'Choose a habit you’d like to make part of your everyday routine.',
          ),
          const SizedBox(height: 16),
        ] else ...[
          for (final habit in controller.activeHabits) ...[
            _HabitCard(
              habit: habit,
              completed: completedIds.contains(habit.id),
              streak:
                  controller.streaks[habit.id] ??
                  const HabitStreaks(current: 0, longest: 0),
              completions: controller.completionsByHabit[habit.id] ?? const [],
              onToggleCompletion: onToggleCompletion,
              onEdit: onEditHabit,
              onArchive: onArchiveHabit,
              onView: onViewHabit,
            ),
            const SizedBox(height: 10),
          ],
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAddHabit,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a habit'),
          ),
        ),
      ],
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({
    required this.habit,
    required this.completed,
    required this.streak,
    required this.completions,
    required this.onToggleCompletion,
    required this.onEdit,
    required this.onArchive,
    required this.onView,
  });

  final Habit habit;
  final bool completed;
  final HabitStreaks streak;
  final List<HabitCompletion> completions;
  final CompletionAction onToggleCompletion;
  final HabitAction onEdit;
  final HabitAction onArchive;
  final HabitAction onView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheduleLabel = switch (habit.scheduleType) {
      HabitScheduleType.daily => 'Every day',
      HabitScheduleType.selectedWeekdays =>
        habit.selectedWeekdays.map(_weekdayShortName).join(' · '),
      HabitScheduleType.weeklyTarget => '${habit.weeklyTarget} times a week',
    };
    final categoryIcon = switch (habit.category.toLowerCase()) {
      'health' => Icons.favorite_border_rounded,
      'mindfulness' => Icons.spa_outlined,
      'learning' => Icons.menu_book_outlined,
      'productivity' => Icons.bolt_rounded,
      _ => Icons.auto_awesome_outlined,
    };
    final accent = theme.colorScheme.tertiary;
    final today = DateTime.now();
    final scheduledToday = HabitSchedule.isScheduledForCheckIn(
      habit: habit,
      date: today,
      completions: completions,
    );
    final completionLabel = switch (habit.scheduleType) {
      HabitScheduleType.daily => 'Daily',
      HabitScheduleType.selectedWeekdays => scheduleLabel,
      HabitScheduleType.weeklyTarget => 'Weekly target',
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onView(habit),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(categoryIcon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${habit.category}  /  $completionLabel',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          habit.scheduleType == HabitScheduleType.weeklyTarget
                              ? '${HabitSchedule.completedInCurrentWeek(habitId: habit.id, completions: completions, asOf: today)}/${habit.weeklyTarget} this week'
                              : completed
                              ? 'Completed today'
                              : scheduledToday
                              ? 'Due today'
                              : 'Rest day',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: completed
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0.1,
                            fontSize: 10,
                          ),
                        ),
                        Text('·', style: theme.textTheme.labelSmall),
                        Icon(
                          Icons.local_fire_department_outlined,
                          size: 14,
                          color: theme.colorScheme.tertiary,
                        ),
                        Text(
                          '${streak.current} day streak',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 0.1,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          'Best ${streak.longest}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 0.1,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    if (habit.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        habit.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Habit options',
                onSelected: (action) {
                  if (action == 'edit') onEdit(habit);
                  if (action == 'archive') onArchive(habit);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
              const SizedBox(width: 8),
              if (completed)
                OutlinedButton.icon(
                  onPressed: () => onToggleCompletion(habit.id, false),
                  icon: const Icon(Icons.undo_rounded, size: 17),
                  label: const Text('Undo'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: theme.colorScheme.primary,
                  ),
                )
              else if (scheduledToday)
                FilledButton.icon(
                  onPressed: () => onToggleCompletion(habit.id, true),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('Complete'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.event_available_outlined,
                  semanticLabel: 'Not scheduled today',
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 7),
                Text(value, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

String _weekdayShortName(int weekday) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[weekday - 1];
}

enum _HistoryRange { daily, weekly, monthly }

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    required this.controller,
    required this.onViewHabit,
    super.key,
  });

  final HabitController controller;
  final HabitAction onViewHabit;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  _HistoryRange _range = _HistoryRange.monthly;
  DateTime _selectedDate = DateTime.now();
  String? _selectedHabitId;
  bool _exportInProgress = false;

  DateTime get _month => DateTime(_selectedDate.year, _selectedDate.month);

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.controller.allHabits.any(
      (habit) => habit.id == _selectedHabitId,
    )) {
      _selectedHabitId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final habits = widget.controller.allHabits;
    final allCompletions = widget.controller.allCompletionsByHabit;
    final asOf = DateTime.now();
    final range = _dateRange();
    final entries = _historyForRange(
      habits: habits,
      completionsByHabit: allCompletions,
      from: range.$1,
      to: range.$2,
      asOf: asOf,
    );
    final selectedHabit = _selectedHabitId == null
        ? null
        : habits.where((habit) => habit.id == _selectedHabitId).firstOrNull;

    return AppPage(
      children: [
        const SectionHeading(
          title: 'History',
          subtitle: 'Look back on the consistency you’re building.',
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _exportInProgress ? null : _downloadHistory,
            icon: _exportInProgress
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(
              _exportInProgress ? 'Preparing workbook…' : 'Download History',
            ),
          ),
        ),
        if (_exportInProgress) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _selectedHabitId ?? '',
          decoration: const InputDecoration(
            labelText: 'Habit',
            prefixIcon: Icon(Icons.filter_list_rounded),
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('All habits', overflow: TextOverflow.ellipsis),
            ),
            for (final habit in habits)
              DropdownMenuItem(
                value: habit.id,
                child: Text(
                  '${habit.name}${habit.status == HabitStatus.archived ? ' · Archived' : ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(
            () => _selectedHabitId = value == null || value.isEmpty
                ? null
                : value,
          ),
        ),
        if (selectedHabit != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => widget.onViewHabit(selectedHabit),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('View habit details'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 340) {
              return Wrap(
                spacing: 8,
                children: [
                  for (final option in _HistoryRange.values)
                    ChoiceChip(
                      label: Text(switch (option) {
                        _HistoryRange.daily => 'Day',
                        _HistoryRange.weekly => 'Week',
                        _HistoryRange.monthly => 'Month',
                      }),
                      selected: _range == option,
                      onSelected: (_) => setState(() => _range = option),
                    ),
                ],
              );
            }
            return SegmentedButton<_HistoryRange>(
              segments: const [
                ButtonSegment(value: _HistoryRange.daily, label: Text('Day')),
                ButtonSegment(value: _HistoryRange.weekly, label: Text('Week')),
                ButtonSegment(
                  value: _HistoryRange.monthly,
                  label: Text('Month'),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (selection) =>
                  setState(() => _range = selection.first),
            );
          },
        ),
        const SizedBox(height: 16),
        HabitCalendar(
          habits: selectedHabit == null ? habits : [selectedHabit],
          completionsByHabit: allCompletions,
          asOf: asOf,
          month: _month,
          selectedDate: _selectedDate,
          onMonthChanged: (date) => setState(() {
            _selectedDate = DateTime(date.year, date.month, 1);
          }),
          onDateSelected: (date) => setState(() => _selectedDate = date),
        ),
        const SizedBox(height: 18),
        SectionHeading(
          title: switch (_range) {
            _HistoryRange.daily => _formatLongDate(_selectedDate),
            _HistoryRange.weekly =>
              '${_formatLongDate(range.$1)} – ${_formatLongDate(range.$2)}',
            _HistoryRange.monthly => _formatMonth(_selectedDate),
          },
          subtitle: selectedHabit?.name ?? 'All habits',
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          AppEmptyState(
            icon: Icons.event_note_rounded,
            title: selectedHabit == null && habits.isEmpty
                ? 'Your story starts here'
                : 'No history for this period',
            message: selectedHabit == null && habits.isEmpty
                ? 'Once you add habits and check in, your history will appear here.'
                : 'There are no completed or missed scheduled check-ins in this date range.',
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < entries.length; index++)
                  ListTile(
                    key: ValueKey(
                      '${entries[index].dateKey}-${entries[index].habit.id}',
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          (entries[index].state == HabitDayState.completed
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error)
                              .withValues(alpha: 0.12),
                      child: Icon(
                        entries[index].state == HabitDayState.completed
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        color: entries[index].state == HabitDayState.completed
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                    ),
                    title: Text(entries[index].habit.name),
                    subtitle: Text(
                      _formatLongDate(
                        HabitSchedule.localDateFromKey(entries[index].dateKey),
                      ),
                    ),
                    trailing: Text(
                      entries[index].state == HabitDayState.completed
                          ? 'Done'
                          : entries[index].weeklyTargetMiss
                          ? 'Target missed'
                          : 'Missed',
                      style: theme.textTheme.labelLarge,
                    ),
                    onTap: () => widget.onViewHabit(entries[index].habit),
                    shape: index == entries.length - 1
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color:
                                  theme.dividerTheme.color ??
                                  theme.colorScheme.outline,
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _downloadHistory() async {
    final request = await showDialog<HistoryExportRequest>(
      context: context,
      builder: (context) => _HistoryExportDialog(
        habits: widget.controller.allHabits,
        selectedHabitId: _selectedHabitId,
        selectedMonth: _selectedDate,
      ),
    );
    if (request == null || !mounted) return;
    setState(() => _exportInProgress = true);
    try {
      final result = await HabitHistoryExportService(
        dataSource: widget.controller.repository,
      ).export(request);
      if (!mounted) return;
      final message = switch (result.shareResult.status) {
        ShareResultStatus.success when result.summaryRowCount == 0 =>
          'Empty workbook created: ${result.file.uri.pathSegments.last}. No habits overlap this selection.',
        ShareResultStatus.success =>
          'Workbook ready: ${result.file.uri.pathSegments.last} '
              '(${result.detailRowCount} history rows).',
        ShareResultStatus.dismissed => 'Workbook created, but sharing was canceled. It remains in app documents.',
        ShareResultStatus.unavailable => 'Workbook created and sent to the share sheet. The receiving app cannot confirm whether it saved the file.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not export history: $error')),
        );
    } finally {
      if (mounted) setState(() => _exportInProgress = false);
    }
  }

  (DateTime, DateTime) _dateRange() {
    final date = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return switch (_range) {
      _HistoryRange.daily => (date, date),
      _HistoryRange.weekly => (
        DateTime(date.year, date.month, date.day - date.weekday + 1),
        DateTime(date.year, date.month, date.day - date.weekday + 7),
      ),
      _HistoryRange.monthly => (
        DateTime(date.year, date.month, 1),
        DateTime(date.year, date.month + 1, 0),
      ),
    };
  }

  List<_HistoryListEntry> _historyForRange({
    required List<Habit> habits,
    required Map<String, List<HabitCompletion>> completionsByHabit,
    required DateTime from,
    required DateTime to,
    required DateTime asOf,
  }) {
    final selectedHabits = _selectedHabitId == null
        ? habits
        : habits.where((habit) => habit.id == _selectedHabitId).toList();
    final entries = <_HistoryListEntry>[];
    for (final habit in selectedHabits) {
      final completions = completionsByHabit[habit.id] ?? const [];
      for (
        var date = from;
        !date.isAfter(to);
        date = DateTime(date.year, date.month, date.day + 1)
      ) {
        final state = HabitSchedule.dayState(
          habit: habit,
          completions: completions,
          date: date,
          asOf: asOf,
        );
        if (state == HabitDayState.completed || state == HabitDayState.missed) {
          entries.add(
            _HistoryListEntry(
              habit: habit,
              dateKey: HabitCompletion.dateKey(date),
              state: state,
              weeklyTargetMiss:
                  state == HabitDayState.missed &&
                  habit.scheduleType == HabitScheduleType.weeklyTarget,
            ),
          );
        }
      }
    }
    entries.sort((a, b) {
      final dateOrder = b.dateKey.compareTo(a.dateKey);
      return dateOrder != 0 ? dateOrder : a.habit.name.compareTo(b.habit.name);
    });
    return entries;
  }
}

enum _HistoryExportScope { all, month, dateRange }

class _HistoryExportDialog extends StatefulWidget {
  const _HistoryExportDialog({
    required this.habits,
    required this.selectedHabitId,
    required this.selectedMonth,
  });

  final List<Habit> habits;
  final String? selectedHabitId;
  final DateTime selectedMonth;

  @override
  State<_HistoryExportDialog> createState() => _HistoryExportDialogState();
}

class _HistoryExportDialogState extends State<_HistoryExportDialog> {
  late _HistoryExportScope _scope = _HistoryExportScope.all;
  late String? _habitId = widget.selectedHabitId;
  late DateTime _startDate = _earlierDate(
    DateTime(widget.selectedMonth.year, widget.selectedMonth.month, 1),
    DateTime.now(),
  );
  late DateTime _endDate = _earlierDate(widget.selectedMonth, DateTime.now());

  Future<void> _chooseDate({required bool start}) async {
    final today = DateTime.now();
    final requestedInitial = start ? _startDate : _endDate;
    final initial = _earlierDate(requestedInitial, today);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = DateTime(selected.year, selected.month, selected.day);
      } else {
        _endDate = DateTime(selected.year, selected.month, selected.day);
      }
    });
  }

  void _export() {
    final monthStart = DateTime(
      widget.selectedMonth.year,
      widget.selectedMonth.month,
    );
    final monthEnd = DateTime(
      widget.selectedMonth.year,
      widget.selectedMonth.month + 1,
      0,
    );
    Navigator.pop(
      context,
      HistoryExportRequest(
        habitId: _habitId,
        startDate: switch (_scope) {
          _HistoryExportScope.all => null,
          _HistoryExportScope.month => monthStart,
          _HistoryExportScope.dateRange => _startDate,
        },
        endDate: switch (_scope) {
          _HistoryExportScope.all => null,
          _HistoryExportScope.month => monthEnd,
          _HistoryExportScope.dateRange => _endDate,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invalidRange =
        _scope == _HistoryExportScope.dateRange &&
        _endDate.isBefore(_startDate);
    return AlertDialog(
      title: const Text('Download history'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<_HistoryExportScope>(
              initialValue: _scope,
              decoration: const InputDecoration(labelText: 'Date range'),
              items: const [
                DropdownMenuItem(
                  value: _HistoryExportScope.all,
                  child: Text('Complete history'),
                ),
                DropdownMenuItem(
                  value: _HistoryExportScope.month,
                  child: Text('Selected month'),
                ),
                DropdownMenuItem(
                  value: _HistoryExportScope.dateRange,
                  child: Text('Choose date range'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _scope = value);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _habitId ?? '',
              decoration: const InputDecoration(labelText: 'Habit'),
              items: [
                const DropdownMenuItem(value: '', child: Text('All habits')),
                for (final habit in widget.habits)
                  DropdownMenuItem(
                    value: habit.id,
                    child: Text(
                      '${habit.name}${habit.status == HabitStatus.archived ? ' · Archived' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(
                () => _habitId = value == null || value.isEmpty ? null : value,
              ),
            ),
            if (_scope == _HistoryExportScope.month) ...[
              const SizedBox(height: 12),
              Text(
                'Month: ${_formatMonth(widget.selectedMonth)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_scope == _HistoryExportScope.dateRange) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _chooseDate(start: true),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        'From ${_dateLabel(_startDate)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _chooseDate(start: false),
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        'To ${_dateLabel(_endDate)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              if (invalidRange)
                Text(
                  'End date must be on or after the start date.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              'Creates a genuine Excel workbook with History and Summary worksheets.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: invalidRange ? null : _export,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Create workbook'),
        ),
      ],
    );
  }
}

String _dateLabel(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _earlierDate(DateTime a, DateTime b) {
  final first = DateTime(a.year, a.month, a.day);
  final second = DateTime(b.year, b.month, b.day);
  return first.isBefore(second) ? first : second;
}

class _HistoryListEntry {
  const _HistoryListEntry({
    required this.habit,
    required this.dateKey,
    required this.state,
    this.weeklyTargetMiss = false,
  });

  final Habit habit;
  final String dateKey;
  final HabitDayState state;
  final bool weeklyTargetMiss;
}

class HabitCalendar extends StatefulWidget {
  const HabitCalendar({
    required this.habits,
    required this.completionsByHabit,
    required this.asOf,
    this.month,
    this.selectedDate,
    this.onMonthChanged,
    this.onDateSelected,
    super.key,
  });

  final List<Habit> habits;
  final Map<String, List<HabitCompletion>> completionsByHabit;
  final DateTime asOf;
  final DateTime? month;
  final DateTime? selectedDate;
  final ValueChanged<DateTime>? onMonthChanged;
  final ValueChanged<DateTime>? onDateSelected;

  @override
  State<HabitCalendar> createState() => _HabitCalendarState();
}

class _HabitCalendarState extends State<HabitCalendar> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth =
        widget.month ?? DateTime(widget.asOf.year, widget.asOf.month);
  }

  @override
  void didUpdateWidget(covariant HabitCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.month != null) _visibleMonth = widget.month!;
  }

  void _moveMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    setState(() => _visibleMonth = next);
    widget.onMonthChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month);
    final gridStart = DateTime(
      firstOfMonth.year,
      firstOfMonth.month,
      1 - (firstOfMonth.weekday - 1),
    );
    final daysInMonth = DateTime(
      firstOfMonth.year,
      firstOfMonth.month + 1,
      0,
    ).day;
    final cellCount = ((firstOfMonth.weekday - 1 + daysInMonth + 6) ~/ 7) * 7;
    const weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    _formatMonth(_visibleMonth),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (var index = 0; index < weekdayLabels.length; index++)
                  Expanded(
                    child: Semantics(
                      label: weekdayNames[index],
                      child: ExcludeSemantics(
                        child: Center(
                          child: Text(
                            weekdayLabels[index],
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 42,
              ),
              itemBuilder: (context, index) {
                final date = DateTime(
                  gridStart.year,
                  gridStart.month,
                  gridStart.day + index,
                );
                final states = _statesFor(date);
                final isCurrentMonth = date.month == _visibleMonth.month;
                final isSelected =
                    widget.selectedDate != null &&
                    HabitCompletion.dateKey(date) ==
                        HabitCompletion.dateKey(widget.selectedDate!);
                final label =
                    '${_formatLongDate(date)}: ${_stateLabels(states)}';
                return Semantics(
                  label: label,
                  selected: isSelected,
                  button: widget.onDateSelected != null,
                  child: Tooltip(
                    message: label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: widget.onDateSelected == null
                          ? null
                          : () => widget.onDateSelected!(date),
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 30,
                              height: 27,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '${date.day}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : isCurrentMonth
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.45),
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (final state in states.take(3))
                                  Container(
                                    width: 4,
                                    height: 4,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _stateColor(theme, state),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 8,
              children: [
                _CalendarLegend(
                  color: theme.colorScheme.primary,
                  label: 'Completed',
                ),
                _CalendarLegend(
                  color: theme.colorScheme.error,
                  label: 'Missed',
                ),
                _CalendarLegend(
                  color: theme.colorScheme.onSurfaceVariant,
                  label: 'Unscheduled',
                ),
                _CalendarLegend(
                  color: theme.colorScheme.tertiary,
                  label: 'Scheduled',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<HabitDayState> _statesFor(DateTime date) {
    if (widget.habits.isEmpty) return [HabitDayState.unscheduled];
    final states = widget.habits
        .map(
          (habit) => HabitSchedule.dayState(
            habit: habit,
            completions: widget.completionsByHabit[habit.id] ?? const [],
            date: date,
            asOf: widget.asOf,
          ),
        )
        .toSet();
    if (states.contains(HabitDayState.completed) ||
        states.contains(HabitDayState.missed) ||
        states.contains(HabitDayState.scheduled)) {
      return [
        if (states.contains(HabitDayState.completed)) HabitDayState.completed,
        if (states.contains(HabitDayState.missed)) HabitDayState.missed,
        if (states.contains(HabitDayState.scheduled)) HabitDayState.scheduled,
      ];
    }
    return [HabitDayState.unscheduled];
  }

  String _stateLabels(List<HabitDayState> states) {
    if (widget.habits.isEmpty) return 'Unscheduled';
    return states
        .map(
          (state) => switch (state) {
            HabitDayState.completed => 'Completed',
            HabitDayState.missed => 'Missed',
            HabitDayState.unscheduled => 'Unscheduled',
            HabitDayState.scheduled => 'Scheduled',
          },
        )
        .join(', ');
  }

  Color _stateColor(ThemeData theme, HabitDayState state) => switch (state) {
    HabitDayState.completed => theme.colorScheme.primary,
    HabitDayState.missed => theme.colorScheme.error,
    HabitDayState.unscheduled => theme.colorScheme.onSurfaceVariant,
    HabitDayState.scheduled => theme.colorScheme.tertiary,
  };
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label calendar indicator',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

String _formatMonth(DateTime date) {
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

String _formatLongDate(DateTime date) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.month}/${date.day}/${date.year}';
}

class HabitHistoryDetail extends StatelessWidget {
  const HabitHistoryDetail({
    required this.habit,
    required this.completions,
    required this.streak,
    required this.asOf,
    required this.onEdit,
    required this.onClose,
    super.key,
  });

  final Habit habit;
  final List<HabitCompletion> completions;
  final HabitStreaks streak;
  final DateTime asOf;
  final VoidCallback onEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = HabitSchedule.summarizeHistory(
      habit: habit,
      completions: completions,
      asOf: asOf,
    );
    final scheduleLabel = switch (habit.scheduleType) {
      HabitScheduleType.daily => 'Every day',
      HabitScheduleType.selectedWeekdays =>
        habit.selectedWeekdays.map(_weekdayShortName).join(' · '),
      HabitScheduleType.weeklyTarget => '${habit.weeklyTarget} times each week',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(habit.name, style: theme.textTheme.headlineMedium),
            ),
            IconButton(
              tooltip: 'Edit habit',
              onPressed: habit.status == HabitStatus.active ? onEdit : null,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Close habit details',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${habit.category}  /  $scheduleLabel'
          '${habit.status == HabitStatus.archived ? '  /  Archived' : ''}',
          style: theme.textTheme.bodyMedium,
        ),
        if (habit.description?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text(habit.description!, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _HabitHistoryMetric(
              label: 'CURRENT STREAK',
              value: '${streak.current}',
            ),
            _HabitHistoryMetric(
              label: 'LONGEST STREAK',
              value: '${streak.longest}',
            ),
            _HabitHistoryMetric(
              label: 'COMPLETED',
              value: '${summary.completedScheduledDays}',
            ),
            _HabitHistoryMetric(
              label: habit.scheduleType == HabitScheduleType.weeklyTarget
                  ? 'MISSED SESSIONS'
                  : 'MISSED DAYS',
              value: '${summary.missedScheduledDays}',
            ),
            _HabitHistoryMetric(
              label: 'COMPLETION',
              value: '${summary.completionPercent}%',
            ),
          ],
        ),
        if (habit.scheduleType == HabitScheduleType.weeklyTarget) ...[
          const SizedBox(height: 8),
          Text(
            'Weekly targets are evaluated after Sunday. Unfilled target sessions are counted as missed; a missed week is marked on its final day.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 18),
        HabitCalendar(
          habits: [habit],
          completionsByHabit: {habit.id: completions},
          asOf: asOf,
        ),
        const SizedBox(height: 18),
        Text('RECENT CHECK-INS', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (completions.isEmpty)
          const AppEmptyState(
            icon: Icons.history_rounded,
            title: 'No check-ins yet',
            message: 'Your actual completed check-ins will appear here.',
          )
        else
          for (final completion in [
            ...completions,
          ]..sort((a, b) => b.localDate.compareTo(a.localDate)))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                completion.status == CompletionStatus.completed
                    ? Icons.check_circle_outline_rounded
                    : Icons.remove_circle_outline_rounded,
                color: completion.status == CompletionStatus.completed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              title: Text(
                _formatLongDate(
                  HabitSchedule.localDateFromKey(completion.localDate),
                ),
              ),
              trailing: Text(
                completion.status == CompletionStatus.completed
                    ? 'Completed'
                    : 'Missed',
              ),
            ),
      ],
    );
  }
}

class _HabitHistoryMetric extends StatelessWidget {
  const _HabitHistoryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  static final _packageInfo = PackageInfo.fromPlatform();

  const SettingsPage({
    required this.controller,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onOpenHistory,
    required this.onError,
    super.key,
  });

  final HabitController controller;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode) onThemeModeChanged;
  final VoidCallback onOpenHistory;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferences = controller.preferences;
    return AppPage(
      children: [
        const SectionHeading(
          title: 'Settings',
          subtitle: 'Make HabitFlow feel like yours.',
        ),
        const SizedBox(height: 24),
        Text('APPEARANCE', style: _eyebrowStyle(theme)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.palette_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text('Theme', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose the look that feels right.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) async {
                    try {
                      await onThemeModeChanged(selection.first);
                    } catch (error) {
                      onError('Could not save theme setting: $error');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('REMINDERS', style: _eyebrowStyle(theme)),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Default reminder for new habits'),
                subtitle: Text(
                  preferences.reminderDefaultEnabled
                      ? 'Default time: ${preferences.reminderDefaultTime}'
                      : 'Off by default',
                ),
                value: preferences.reminderDefaultEnabled,
                onChanged: (enabled) => _updatePreferences(
                  context,
                  preferences.copyWith(reminderDefaultEnabled: enabled),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.schedule_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Default reminder time'),
                subtitle: Text(preferences.reminderDefaultTime),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _chooseDefaultReminderTime(context, preferences),
              ),
              ListTile(
                leading: Icon(
                  Icons.notifications_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Notification permissions'),
                subtitle: const Text('Manage alerts in Android settings'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () async {
                  try {
                    await controller.openNotificationSettings();
                  } catch (error) {
                    onError('Could not open notification settings: $error');
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                child: Text(
                  'Reminders are optional and scheduled on this device. '
                  'Delivery may be delayed or prevented by battery restrictions, '
                  'Do Not Disturb, or other system settings.',
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('HISTORY', style: _eyebrowStyle(theme)),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.file_download_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Export history'),
            subtitle: const Text('Create and share an Excel workbook'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onOpenHistory,
          ),
        ),
        const SizedBox(height: 24),
        Text('ARCHIVED HABITS', style: _eyebrowStyle(theme)),
        const SizedBox(height: 10),
        _ArchivedHabitsCard(controller: controller, onError: onError),
        const SizedBox(height: 24),
        Text('ABOUT', style: _eyebrowStyle(theme)),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.phone_android_rounded,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('HabitFlow'),
                subtitle: FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Version information unavailable');
                    }
                    if (!snapshot.hasData) {
                      return const Text('Loading version…');
                    }
                    return Text('Version ${snapshot.data!.version}');
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Text(
                  'Build consistency, one day at a time.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your privacy', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Habit records and settings are stored locally on this '
                        'device. HabitFlow has no account, cloud sync, or '
                        'remote backup. Clearing app data or uninstalling the '
                        'app removes local records.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('DATA', style: _eyebrowStyle(theme)),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
            title: const Text('Clear all local data'),
            subtitle: const Text('Permanently remove habits and history'),
            onTap: () => _confirmClearAll(context),
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: Text(
            'HabitFlow  •  Build consistency, one day at a time.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _updatePreferences(
    BuildContext context,
    HabitPreferences preferences,
  ) async {
    try {
      await controller.updatePreferences(preferences);
    } catch (error) {
      onError('Could not save reminder settings: $error');
    }
  }

  Future<void> _chooseDefaultReminderTime(
    BuildContext context,
    HabitPreferences preferences,
  ) async {
    final parts = preferences.reminderDefaultTime.split(':').map(int.parse);
    final initial = parts.toList();
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial[0], minute: initial[1]),
    );
    if (selected == null || !context.mounted) return;
    final time =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    await _updatePreferences(
      context,
      preferences.copyWith(reminderDefaultTime: time),
    );
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => const _ClearAllDataDialog(),
    );
    if (clear != true || !context.mounted) return;
    try {
      await controller.clearAllData();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All local habits and history were cleared.'),
        ),
      );
    } catch (error) {
      onError('Could not clear local data: $error');
    }
  }

  TextStyle? _eyebrowStyle(ThemeData theme) {
    return theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.primary,
      fontSize: 11,
      letterSpacing: 1.1,
    );
  }
}

class _ClearAllDataDialog extends StatefulWidget {
  const _ClearAllDataDialog();

  @override
  State<_ClearAllDataDialog> createState() => _ClearAllDataDialogState();
}

class _ClearAllDataDialogState extends State<_ClearAllDataDialog> {
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
      title: const Text('Clear all local data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes every habit and all completion history '
            'from this device, and resets local settings. This cannot be '
            'undone. Archiving a habit does not clear its history.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmation,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Type CLEAR to confirm',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _confirmation.text.trim() == 'CLEAR'
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Clear everything'),
        ),
      ],
    );
  }
}

class _ArchivedHabitsCard extends StatelessWidget {
  const _ArchivedHabitsCard({required this.controller, required this.onError});

  final HabitController controller;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final archived = controller.allHabits
        .where((habit) => habit.status == HabitStatus.archived)
        .toList(growable: false);
    if (archived.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Habits you archive will appear here. Their history stays saved, '
            'and you can restore them anytime.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < archived.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.archive_outlined,
                color: theme.colorScheme.secondary,
              ),
              title: Text(archived[index].name),
              subtitle: Text('${archived[index].category} · History retained'),
              trailing: TextButton.icon(
                onPressed: () => _restore(context, archived[index]),
                icon: const Icon(Icons.unarchive_outlined),
                label: const Text('Restore'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, Habit habit) async {
    try {
      final result = await controller.restoreArchivedHabit(habit.id);
      if (!context.mounted) return;
      if (result == ReminderSyncStatus.permissionDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${habit.name} was restored, but its reminder is off because '
              'notifications are not allowed.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${habit.name} was restored.')));
      }
    } on HabitReminderSyncException catch (error) {
      onError(error.toString());
    } catch (error) {
      onError('Could not restore ${habit.name}: $error');
    }
  }
}
