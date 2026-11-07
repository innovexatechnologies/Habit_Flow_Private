import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'app_theme.dart';
import 'data/habit_controller.dart';
import 'data/habit_database.dart';
import 'data/local_habit_reminder_service.dart';

void main() {
  runApp(const HabitFlowApp());
}

class HabitFlowApp extends StatefulWidget {
  const HabitFlowApp({
    this.database,
    this.dataSource,
    this.reminderService,
    super.key,
  });

  final HabitDatabase? database;
  final HabitDataSource? dataSource;
  final HabitReminderService? reminderService;

  @override
  State<HabitFlowApp> createState() => _HabitFlowAppState();
}

class _HabitFlowAppState extends State<HabitFlowApp> {
  ThemeMode _themeMode = ThemeMode.light;
  late final HabitController _controller;
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _controller = HabitController(
      widget.dataSource ?? HabitRepository(widget.database ?? HabitDatabase()),
      reminderService:
          widget.reminderService ??
          (widget.dataSource == null ? LocalHabitReminderService() : null),
    );
    _controller.addListener(_onControllerChanged);
    _initialization = _controller.initialize();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() => _themeMode = _controller.preferences.themeMode);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _setThemeMode(ThemeMode mode) {
    return _controller.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HabitFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _DatabaseErrorPage(
              error: snapshot.error!,
              onRetry: () {
                setState(() {
                  _initialization = _controller.initialize();
                });
              },
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return HabitFlowShell(
            controller: _controller,
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
          );
        },
      ),
    );
  }
}

class _DatabaseErrorPage extends StatelessWidget {
  const _DatabaseErrorPage({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage_rounded, size: 44),
              const SizedBox(height: 16),
              Text(
                'HabitFlow couldn’t open its local database.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
