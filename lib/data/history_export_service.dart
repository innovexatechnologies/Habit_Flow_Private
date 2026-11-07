import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'habit.dart';
import 'habit_database.dart';
import 'habit_schedule.dart';

@immutable
class HistoryExportRequest {
  const HistoryExportRequest({this.habitId, this.startDate, this.endDate});

  final String? habitId;
  final DateTime? startDate;
  final DateTime? endDate;
}

@immutable
class HistoryExportResult {
  const HistoryExportResult({
    required this.file,
    required this.detailRowCount,
    required this.summaryRowCount,
    required this.shareResult,
  });

  final File file;
  final int detailRowCount;
  final int summaryRowCount;
  final ShareResult shareResult;
}

typedef HistoryFileSharer = Future<ShareResult> Function(File file);

class HistoryExportShareException implements Exception {
  const HistoryExportShareException(this.file, this.cause);

  final File file;
  final Object cause;

  @override
  String toString() =>
      'The workbook was created at ${file.path}, but the share sheet failed: $cause';
}

class HabitHistoryExportService {
  HabitHistoryExportService({
    required this.dataSource,
    DateTime Function()? now,
    Future<Directory> Function()? documentsDirectory,
    HistoryFileSharer? shareFile,
  }) : _now = now ?? DateTime.now,
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _shareFile = shareFile ?? _shareWithAndroid;

  final HabitDataSource dataSource;
  final DateTime Function() _now;
  final Future<Directory> Function() _documentsDirectory;
  final HistoryFileSharer _shareFile;

  Future<HistoryExportResult> export(HistoryExportRequest request) async {
    final start = request.startDate == null
        ? null
        : _dateOnly(request.startDate!);
    final end = request.endDate == null ? null : _dateOnly(request.endDate!);
    if ((start == null) != (end == null)) {
      throw ArgumentError('Choose both a start date and an end date.');
    }
    if (start != null && end!.isBefore(start)) {
      throw ArgumentError('The end date must be on or after the start date.');
    }

    final now = _now();
    final today = _dateOnly(now);
    final allHabits = await dataSource.getHabits(includeArchived: true);
    final habits = request.habitId == null
        ? allHabits
        : allHabits
              .where((habit) => habit.id == request.habitId)
              .toList(growable: false);
    if (request.habitId != null && habits.isEmpty) {
      throw StateError('The selected habit no longer exists.');
    }

    final completions = await dataSource.getCompletionsForHabits(
      habits.map((habit) => habit.id).toList(growable: false),
    );
    final workbook = _createWorkbook(
      habits: habits,
      completionsByHabit: completions,
      start: start,
      end: end,
      today: today,
      now: now,
    );

    final directory = await _documentsDirectory();
    final exportDirectory = Directory(
      p.join(directory.path, 'HabitFlow', 'exports'),
    );
    await exportDirectory.create(recursive: true);
    final file = File(
      p.join(exportDirectory.path, _fileName(start, end, today)),
    );
    final bytes = workbook.excel.save();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Excel workbook generation returned no file data.');
    }
    await file.writeAsBytes(bytes, flush: true);
    if (!await file.exists() || await file.length() == 0) {
      throw FileSystemException(
        'The generated workbook could not be verified.',
        file.path,
      );
    }
    final verifiedWorkbook = Excel.decodeBytes(await file.readAsBytes());
    if (!verifiedWorkbook.tables.containsKey('History') ||
        !verifiedWorkbook.tables.containsKey('Summary') ||
        verifiedWorkbook.tables['History']!.rows.length !=
            workbook.detailRowCount + 1 ||
        verifiedWorkbook.tables['Summary']!.rows.length !=
            workbook.summaryRowCount + 1) {
      throw FormatException('The generated workbook failed content verification.');
    }

    ShareResult shareResult;
    try {
      shareResult = await _shareFile(file);
    } catch (error) {
      throw HistoryExportShareException(file, error);
    }
    return HistoryExportResult(
      file: file,
      detailRowCount: workbook.detailRowCount,
      summaryRowCount: workbook.summaryRowCount,
      shareResult: shareResult,
    );
  }

  _BuiltWorkbook _createWorkbook({
    required List<Habit> habits,
    required Map<String, List<HabitCompletion>> completionsByHabit,
    required DateTime? start,
    required DateTime? end,
    required DateTime today,
    required DateTime now,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet == null) {
      throw StateError(
        'The Excel package did not create its default worksheet.',
      );
    }
    excel.rename(defaultSheet, 'History');
    excel.setDefaultSheet('History');
    final detail = excel['History'];
    final summary = excel['Summary'];
    const detailHeaders = [
      'Date',
      'Habit ID',
      'Habit Name',
      'Category',
      'Scheduled',
      'Completion Status',
      'Completion Timestamp',
      'Current/Calculated Streak',
    ];
    const summaryHeaders = [
      'Habit Name',
      'Date Range',
      'Scheduled Days',
      'Completed Days',
      'Missed Days',
      'Completion Percentage',
      'Longest Streak',
    ];
    _writeRow(detail, 0, detailHeaders);
    _writeRow(summary, 0, summaryHeaders);

    var detailRows = 0;
    var summaryRows = 0;
    for (final habit in habits) {
      final records = completionsByHabit[habit.id] ?? const [];
      final habitStart = _dateOnly(habit.createdAt);
      final habitEnd = habit.status == HabitStatus.archived
          ? _earlier(_dateOnly(habit.updatedAt), today)
          : today;
      final rowStart = start == null ? habitStart : _later(start, habitStart);
      final rowEnd = end == null ? habitEnd : _earlier(end, habitEnd);
      if (rowEnd.isBefore(rowStart)) continue;

      final stats = _countHistory(
        habit: habit,
        records: records,
        start: rowStart,
        end: rowEnd,
        today: today,
      );
      final longest = HabitSchedule.calculateStreaks(
        habit: habit,
        completions: records,
        asOf: habit.status == HabitStatus.archived ? habitEnd : today,
      ).longest;
      summaryRows++;
      _writeRow(summary, summaryRows, [
        habit.name,
        '${HabitCompletion.dateKey(rowStart)} to ${HabitCompletion.dateKey(rowEnd)}',
        stats.scheduled,
        stats.completed,
        stats.missed,
        stats.scheduled == 0
            ? '0%'
            : '${(stats.completed * 100 / stats.scheduled).round()}%',
        longest,
      ]);

      final recordByDate = {
        for (final record in records) record.localDate: record,
      };
      for (
        var date = rowStart;
        !date.isAfter(rowEnd);
        date = DateTime(date.year, date.month, date.day + 1)
      ) {
        final key = HabitCompletion.dateKey(date);
        final state = HabitSchedule.dayState(
          habit: habit,
          completions: records,
          date: date,
          asOf: now,
        );
        final record = recordByDate[key];
        final effectiveState = record?.status == CompletionStatus.completed
            ? HabitDayState.completed
            : record?.status == CompletionStatus.missed
            ? HabitDayState.missed
            : state;
        final scheduled = effectiveState != HabitDayState.unscheduled;
        final streakDate = _dateOnly(date).isBefore(today)
            ? DateTime(date.year, date.month, date.day + 1)
            : now;
        final streak =
            effectiveState == HabitDayState.unscheduled ||
                (habit.scheduleType == HabitScheduleType.weeklyTarget &&
                    date.weekday != DateTime.sunday &&
                    effectiveState != HabitDayState.completed)
            ? ''
            : HabitSchedule.calculateStreaks(
                habit: habit,
                completions: records,
                asOf: streakDate,
              ).current;
        detailRows++;
        _writeRow(detail, detailRows, [
          key,
          habit.id,
          habit.name,
          habit.category,
          scheduled ? 'Yes' : 'No',
          _statusLabel(effectiveState),
          record?.completedAt?.toIso8601String() ?? '',
          streak,
        ]);
      }
    }

    return _BuiltWorkbook(
      excel: excel,
      detailRowCount: detailRows,
      summaryRowCount: summaryRows,
    );
  }

  _HistoryCounts _countHistory({
    required Habit habit,
    required List<HabitCompletion> records,
    required DateTime start,
    required DateTime end,
    required DateTime today,
  }) {
    final counts = HabitSchedule.summarizePeriod(
      habit: habit,
      completions: records,
      start: start,
      end: end,
      asOf: today,
    );
    return _HistoryCounts(
      scheduled: counts.scheduled,
      completed: counts.completed,
      missed: counts.missed,
    );
  }

  static Future<ShareResult> _shareWithAndroid(File file) {
    return SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'HabitFlow history',
        text: 'HabitFlow history workbook',
      ),
    );
  }

  static void _writeRow(Sheet sheet, int row, List<Object?> values) {
    for (var column = 0; column < values.length; column++) {
      final value = values[column];
      final cellValue = switch (value) {
        int value => IntCellValue(value),
        double value => DoubleCellValue(value),
        _ => TextCellValue(value?.toString() ?? ''),
      };
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
        cellValue,
      );
    }
  }

  static String _statusLabel(HabitDayState state) => switch (state) {
    HabitDayState.completed => 'Completed',
    HabitDayState.missed => 'Missed',
    HabitDayState.scheduled => 'Scheduled',
    HabitDayState.unscheduled => 'Unscheduled',
  };

  static String _fileName(DateTime? start, DateTime? end, DateTime today) {
    if (start == null || end == null) {
      return 'HabitFlow_History_All_${HabitCompletion.dateKey(today)}.xlsx';
    }
    final lastDayOfMonth = DateTime(end.year, end.month + 1, 0).day;
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == 1 &&
        end.day == lastDayOfMonth) {
      final month =
          '${start.year.toString().padLeft(4, '0')}-'
          '${start.month.toString().padLeft(2, '0')}';
      return 'HabitFlow_History_$month.xlsx';
    }
    return 'HabitFlow_History_${HabitCompletion.dateKey(start)}_to_'
        '${HabitCompletion.dateKey(end)}.xlsx';
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _earlier(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

  static DateTime _later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
}

class _HistoryCounts {
  const _HistoryCounts({
    required this.scheduled,
    required this.completed,
    required this.missed,
  });

  final int scheduled;
  final int completed;
  final int missed;
}

class _BuiltWorkbook {
  const _BuiltWorkbook({
    required this.excel,
    required this.detailRowCount,
    required this.summaryRowCount,
  });

  final Excel excel;
  final int detailRowCount;
  final int summaryRowCount;
}
