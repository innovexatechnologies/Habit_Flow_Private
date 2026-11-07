import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'habit.dart';
import 'habit_schedule.dart';

class HabitDatabase {
  HabitDatabase({this.databasePath, DatabaseFactory? databaseFactory})
    : _databaseFactory = databaseFactory ?? sqfliteDatabaseFactory;

  static const schemaVersion = 1;

  final String? databasePath;
  final DatabaseFactory _databaseFactory;
  Future<Database>? _opening;

  Future<Database> get database async {
    final current = _opening;
    if (current != null) return current;

    final opening = _open();
    _opening = opening;
    try {
      return await opening;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening == null) return;
    final db = await opening;
    await db.close();
    _opening = null;
  }

  Future<Database> _open() async {
    final path =
        databasePath ??
        p.join(await _databaseFactory.getDatabasesPath(), 'habit_flow.db');
    return _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        case 1:
          await _createSchema(db, version);
        default:
          throw StateError(
            'No database migration is defined for version $version.',
          );
      }
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        category TEXT NOT NULL,
        schedule_type TEXT NOT NULL
          CHECK (schedule_type IN ('daily', 'selectedWeekdays', 'weeklyTarget')),
        selected_weekdays TEXT NOT NULL DEFAULT '',
        weekly_target INTEGER,
        reminder_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (reminder_enabled IN (0, 1)),
        reminder_time TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK (status IN ('active', 'archived')),
        CHECK (weekly_target IS NULL OR weekly_target BETWEEN 1 AND 7)
      )
    ''');
    await db.execute('''
      CREATE TABLE habit_completions (
        id TEXT PRIMARY KEY NOT NULL,
        habit_id TEXT NOT NULL,
        local_date TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('completed', 'missed')),
        completed_at TEXT,
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE RESTRICT,
        UNIQUE (habit_id, local_date)
      )
    ''');
    await db.execute(
      'CREATE INDEX habit_completions_date_idx '
      'ON habit_completions(local_date)',
    );
    await db.execute('''
      CREATE TABLE preferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        theme_mode TEXT NOT NULL DEFAULT 'light'
          CHECK (theme_mode IN ('light', 'dark', 'system')),
        reminder_default_enabled INTEGER NOT NULL DEFAULT 0
          CHECK (reminder_default_enabled IN (0, 1)),
        reminder_default_time TEXT NOT NULL DEFAULT '09:00'
      )
    ''');
    await db.insert('preferences', {'id': 1});
  }
}

abstract interface class HabitDataSource {
  Future<List<Habit>> getHabits({bool includeArchived = false});
  Future<List<HabitCompletion>> getCompletionsForDate(DateTime date);
  Future<List<HabitCompletion>> getCompletionsForHabit(String habitId);
  Future<Map<String, List<HabitCompletion>>> getCompletionsForHabits(
    List<String> habitIds,
  );
  Future<List<HabitHistoryEntry>> getRecentHistory({int limit = 100});
  Future<List<HabitHistoryEntry>> getAllHistory();
  Future<void> saveHabit(Habit habit);
  Future<void> archiveHabit(String id);
  Future<void> setCompletion({
    required String habitId,
    required DateTime date,
    required CompletionStatus status,
  });
  Future<void> undoCompletion({
    required String habitId,
    required DateTime date,
  });
  Future<HabitPreferences> getPreferences();
  Future<void> savePreferences(HabitPreferences preferences);
  Future<void> clearAllData();
}

class HabitRepository implements HabitDataSource {
  HabitRepository(this.database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final HabitDatabase database;
  final DateTime Function() _now;

  @override
  Future<List<Habit>> getHabits({bool includeArchived = false}) async {
    final db = await database.database;
    final rows = await db.query(
      'habits',
      where: includeArchived ? null : 'status = ?',
      whereArgs: includeArchived ? null : ['active'],
      orderBy: 'created_at DESC',
    );
    return rows.map(_habitFromRow).toList(growable: false);
  }

  @override
  Future<List<HabitCompletion>> getCompletionsForDate(DateTime date) async {
    final db = await database.database;
    final rows = await db.query(
      'habit_completions',
      where: 'local_date = ?',
      whereArgs: [HabitCompletion.dateKey(date)],
    );
    return rows.map(_completionFromRow).toList(growable: false);
  }

  @override
  Future<List<HabitCompletion>> getCompletionsForHabit(String habitId) async {
    final db = await database.database;
    final rows = await db.query(
      'habit_completions',
      where: 'habit_id = ?',
      whereArgs: [habitId],
      orderBy: 'local_date ASC',
    );
    return rows.map(_completionFromRow).toList(growable: false);
  }

  @override
  Future<Map<String, List<HabitCompletion>>> getCompletionsForHabits(
    List<String> habitIds,
  ) async {
    if (habitIds.isEmpty) return const {};
    final db = await database.database;
    final rows = await db.query(
      'habit_completions',
      where: 'habit_id IN (${List.filled(habitIds.length, '?').join(',')})',
      whereArgs: habitIds,
      orderBy: 'local_date ASC',
    );
    final grouped = <String, List<HabitCompletion>>{
      for (final id in habitIds) id: <HabitCompletion>[],
    };
    for (final row in rows) {
      final completion = _completionFromRow(row);
      grouped[completion.habitId]?.add(completion);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    };
  }

  @override
  Future<List<HabitHistoryEntry>> getRecentHistory({int limit = 100}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final db = await database.database;
    final rows = await db.rawQuery(
      '''
      SELECT c.id, c.habit_id, c.local_date, c.status, c.completed_at,
             h.name AS habit_name
      FROM habit_completions c
      INNER JOIN habits h ON h.id = c.habit_id
      ORDER BY c.local_date DESC, c.completed_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows
        .map(
          (row) => HabitHistoryEntry(
            completion: _completionFromRow(row),
            habitName: row['habit_name']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<HabitHistoryEntry>> getAllHistory() async {
    final db = await database.database;
    final rows = await db.rawQuery('''
      SELECT c.id, c.habit_id, c.local_date, c.status, c.completed_at,
             h.name AS habit_name
      FROM habit_completions c
      INNER JOIN habits h ON h.id = c.habit_id
      ORDER BY c.local_date DESC, c.completed_at DESC
    ''');
    return rows
        .map(
          (row) => HabitHistoryEntry(
            completion: _completionFromRow(row),
            habitName: row['habit_name']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveHabit(Habit habit) async {
    final name = habit.name.trim();
    if (name.isEmpty) throw ArgumentError('Habit name cannot be empty.');
    if (habit.scheduleType == HabitScheduleType.selectedWeekdays &&
        (habit.selectedWeekdays.isEmpty ||
            habit.selectedWeekdays.any((day) => day < 1 || day > 7))) {
      throw ArgumentError('Choose at least one valid weekday.');
    }
    if (habit.scheduleType == HabitScheduleType.weeklyTarget &&
        (habit.weeklyTarget == null ||
            habit.weeklyTarget! < 1 ||
            habit.weeklyTarget! > 7)) {
      throw ArgumentError('Weekly target must be between 1 and 7.');
    }
    final db = await database.database;
    final row = _habitToRow(habit, name: name);
    await db.transaction((txn) async {
      final existing = await txn.query(
        'habits',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [habit.id],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('habits', row);
      } else {
        row.remove('id');
        row.remove('created_at');
        row['updated_at'] = DateTime.now().toIso8601String();
        await txn.update('habits', row, where: 'id = ?', whereArgs: [habit.id]);
      }
    });
  }

  @override
  Future<void> archiveHabit(String id) async {
    final db = await database.database;
    final count = await db.update(
      'habits',
      {'status': HabitStatus.archived.name, 'updated_at': _nowIso()},
      where: 'id = ? AND status = ?',
      whereArgs: [id, HabitStatus.active.name],
    );
    if (count == 0) throw StateError('The active habit was not found.');
  }

  @override
  Future<void> setCompletion({
    required String habitId,
    required DateTime date,
    required CompletionStatus status,
  }) async {
    final now = _now();
    final key = HabitCompletion.dateKey(date);
    final todayKey = HabitCompletion.dateKey(now);
    if (key != todayKey) {
      throw ArgumentError(
        'Check-ins can only be changed for the local current date.',
      );
    }
    if (status != CompletionStatus.completed) {
      throw ArgumentError('Only completed check-ins can be saved directly.');
    }
    final db = await database.database;
    await db.transaction((txn) async {
      final habitRows = await txn.query(
        'habits',
        where: 'id = ? AND status = ?',
        whereArgs: [habitId, HabitStatus.active.name],
        limit: 1,
      );
      if (habitRows.isEmpty) {
        throw StateError('Only an active habit can be checked in.');
      }
      final habit = _habitFromRow(habitRows.single);
      final completionRows = await txn.query(
        'habit_completions',
        where: 'habit_id = ?',
        whereArgs: [habitId],
      );
      final completions = completionRows.map(_completionFromRow).toList();
      if (!HabitSchedule.isScheduledForCheckIn(
        habit: habit,
        date: date,
        completions: completions,
      )) {
        throw StateError('This habit is not scheduled for today.');
      }
      await txn.execute(
        '''
        INSERT INTO habit_completions
          (id, habit_id, local_date, status, completed_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(habit_id, local_date) DO UPDATE SET
          status = excluded.status,
          completed_at = excluded.completed_at
        ''',
        [
          HabitCompletion(habitId: habitId, localDate: key, status: status).id,
          habitId,
          key,
          status.name,
          now.toIso8601String(),
        ],
      );
    });
  }

  @override
  Future<void> undoCompletion({
    required String habitId,
    required DateTime date,
  }) async {
    final key = HabitCompletion.dateKey(date);
    if (key != HabitCompletion.dateKey(_now())) {
      throw ArgumentError('Only today’s check-in can be undone.');
    }
    final db = await database.database;
    await db.transaction((txn) async {
      final habits = await txn.query(
        'habits',
        columns: ['id'],
        where: 'id = ? AND status = ?',
        whereArgs: [habitId, HabitStatus.active.name],
        limit: 1,
      );
      if (habits.isEmpty) {
        throw StateError('Only an active habit check-in can be undone.');
      }
      await txn.delete(
        'habit_completions',
        where: 'habit_id = ? AND local_date = ?',
        whereArgs: [habitId, key],
      );
    });
  }

  @override
  Future<HabitPreferences> getPreferences() async {
    final db = await database.database;
    final row = (await db.query('preferences', where: 'id = 1')).single;
    return HabitPreferences(
      themeMode: ThemeMode.values.byName(row['theme_mode']! as String),
      reminderDefaultEnabled: row['reminder_default_enabled'] == 1,
      reminderDefaultTime: row['reminder_default_time']! as String,
    );
  }

  @override
  Future<void> savePreferences(HabitPreferences preferences) async {
    final db = await database.database;
    await db.insert('preferences', {
      'id': 1,
      'theme_mode': preferences.themeMode.name,
      'reminder_default_enabled': preferences.reminderDefaultEnabled ? 1 : 0,
      'reminder_default_time': preferences.reminderDefaultTime,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearAllData() async {
    final db = await database.database;
    await db.transaction((txn) async {
      await txn.delete('habit_completions');
      await txn.delete('habits');
      await txn.update('preferences', {
        'theme_mode': ThemeMode.light.name,
        'reminder_default_enabled': 0,
        'reminder_default_time': '09:00',
      }, where: 'id = 1');
    });
  }

  Map<String, Object?> _habitToRow(Habit habit, {required String name}) => {
    'id': habit.id,
    'name': name,
    'description': _emptyToNull(habit.description),
    'category': habit.category,
    'schedule_type': habit.scheduleType.name,
    'selected_weekdays': (habit.selectedWeekdays.toSet().toList()..sort()).join(
      ',',
    ),
    'weekly_target': habit.scheduleType == HabitScheduleType.weeklyTarget
        ? habit.weeklyTarget
        : null,
    'reminder_enabled': habit.reminderEnabled ? 1 : 0,
    'reminder_time': habit.reminderEnabled ? habit.reminderTime : null,
    'created_at': habit.createdAt.toIso8601String(),
    'updated_at': habit.updatedAt.toIso8601String(),
    'status': habit.status.name,
  };

  Habit _habitFromRow(Map<String, Object?> row) {
    final weekdays = row['selected_weekdays']! as String;
    return Habit(
      id: row['id']! as String,
      name: row['name']! as String,
      description: row['description'] as String?,
      category: row['category']! as String,
      scheduleType: HabitScheduleType.values.byName(
        row['schedule_type']! as String,
      ),
      selectedWeekdays: weekdays.isEmpty
          ? const []
          : weekdays.split(',').map(int.parse).toList(growable: false),
      weeklyTarget: row['weekly_target'] as int?,
      reminderEnabled: row['reminder_enabled'] == 1,
      reminderTime: row['reminder_time'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      status: HabitStatus.values.byName(row['status']! as String),
    );
  }

  HabitCompletion _completionFromRow(Map<String, Object?> row) =>
      HabitCompletion(
        id: row['id']! as String,
        habitId: row['habit_id']! as String,
        localDate: row['local_date']! as String,
        status: CompletionStatus.values.byName(row['status']! as String),
        completedAt: row['completed_at'] == null
            ? null
            : DateTime.parse(row['completed_at']! as String),
      );

  String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _nowIso() => _now().toIso8601String();
}

DatabaseFactory get sqfliteDatabaseFactory => databaseFactory;
