import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/models/pending_note_edit.dart';
import 'package:sophie/models/pending_task_edit.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/screens/notes_screen.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/screens/tasks_screen.dart';
import 'package:sophie/services/storage.dart';

class HomeScreen extends StatefulWidget {
  final BackendClient client;
  final VoidCallback onLoggedOut;

  const HomeScreen({
    super.key,
    required this.client,
    required this.onLoggedOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _navChannel = MethodChannel('sophie/navigation');
  static const _navEvents = EventChannel('sophie/navigation/events');

  int _selectedIndex = 0;
  late Future<DashboardData> _dataFuture;
  bool _usingCache = false;
  StreamSubscription? _navEventSub;
  StreamSubscription? _refreshSub;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    _refreshSub = AlertNotifications.refreshRequests.listen((_) => _refresh());
    // Background case: app already running, widget tapped → onNewIntent fires.
    _navEventSub = _navEvents.receiveBroadcastStream().listen((route) {
      if (route == 'tasks' && mounted) setState(() => _selectedIndex = 1);
    });
    // Cold-start case: app launched from widget.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final route = await _navChannel.invokeMethod<String>('getInitialRoute');
      if (route == 'tasks' && mounted) setState(() => _selectedIndex = 1);
    });
  }

  @override
  void dispose() {
    _navEventSub?.cancel();
    _refreshSub?.cancel();
    super.dispose();
  }

  static Future<void> _pushTasksToWidget(List<Task> tasks) async {
    final pending = tasks.where((t) => t.doneAt == null).toList();
    final json = jsonEncode(
      pending
          .map(
            (t) => {
              'id': t.id,
              'text': t.text,
              'dueAt': t.dueAt?.toIso8601String(),
              'color': t.color,
            },
          )
          .toList(),
    );
    await HomeWidget.saveWidgetData<String>('tasks_json', json);
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.example.sophie.TasksWidgetReceiver',
    );
  }

  Future<DashboardData> _loadData() async {
    final hadConflict = await _syncPendingEdits();
    await _syncPendingTaskEdits();
    if (hadConflict) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'An offline edit conflicted with a newer version. '
                'The most recent was kept. Check note history if you need to recover yours.',
              ),
              duration: Duration(seconds: 10),
            ),
          );
        }
      });
    }
    try {
      final data = await widget.client.getDashboardData();
      await AlertNotifications.rescheduleAll(data.tasks);
      await Storage.saveDashboardData(data);
      if (Platform.isAndroid) {
        await _pushTasksToWidget(data.tasks);
      }

      if (mounted) setState(() => _usingCache = false);
      return data;
    } catch (error) {
      final cached = Storage.getDashboardData();
      if (cached != null) {
        if (mounted) setState(() => _usingCache = true);
        return cached;
      }
      rethrow;
    }
  }

  /// Drains the offline edit queue, syncing each pending edit to the server.
  /// Returns true if any edit resulted in a LWW conflict.
  Future<bool> _syncPendingEdits() async {
    List<PendingNoteEdit> pending;
    try {
      pending = await Storage.getPendingNoteEdits();
    } catch (_) {
      return false;
    }
    if (pending.isEmpty) return false;

    bool anyConflict = false;
    for (final edit in pending) {
      try {
        if (edit.isNew) {
          await widget.client.note.saveNote(
            null,
            edit.text,
            collaborators: edit.collaborators,
            color: edit.color,
            dontFold: edit.dontFold,
            todoList: edit.todoList,
          );
        } else {
          final conflicted = await widget.client.note.syncOfflineEdit(
            noteId: edit.noteId,
            text: edit.text,
            collaborators: edit.collaborators,
            color: edit.color,
            dontFold: edit.dontFold,
            todoList: edit.todoList,
            baseUpdatedAt: edit.baseUpdatedAt!,
            localSavedAt: edit.localSavedAt,
          );
          if (conflicted) anyConflict = true;
        }
        await Storage.removePendingNoteEdit(edit.noteId);
      } on UnauthorizedException {
        await Storage.removePendingNoteEdit(edit.noteId);
      } on NoteGoneException {
        // Note deleted or access revoked — discard silently.
        await Storage.removePendingNoteEdit(edit.noteId);
      } catch (_) {
        // Network error or note currently locked — leave for next attempt.
      }
    }
    return anyConflict;
  }

  void _refresh() {
    setState(() {
      _usingCache = false;
      _dataFuture = _loadData();
    });
  }

  /// Drains the offline task queue, syncing each pending create/edit to the server.
  Future<void> _syncPendingTaskEdits() async {
    List<PendingTaskEdit> pending;
    try {
      pending = await Storage.getPendingTaskEdits();
    } catch (_) {
      return;
    }
    if (pending.isEmpty) return;

    for (final edit in pending) {
      try {
        final alerts = edit.alerts.map((a) {
          if (a['type'] == 'absolute') {
            return (
              alertAt: DateTime.parse(a['alertAt'] as String),
              timeBefore: null as Duration?,
            );
          }
          final parts = (a['timeBefore'] as String).split(':');
          final h = int.tryParse(parts[0]) ?? 0;
          final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
          return (
            alertAt: null as DateTime?,
            timeBefore: Duration(hours: h, minutes: m),
          );
        }).toList();

        final dueAt = edit.dueAt != null ? DateTime.parse(edit.dueAt!) : null;

        await widget.client.task.saveTask(
          edit.isNew ? null : edit.taskId,
          edit.text,
          rrule: edit.rrule,
          dueAt: dueAt,
          color: edit.color,
          collaboratorIds: edit.collaboratorIds,
          alerts: alerts,
        );
        await Storage.removePendingTaskEdit(edit.taskId);
      } on UnauthorizedException {
        await Storage.removePendingTaskEdit(edit.taskId);
      } catch (_) {
        // Network error — leave for next attempt.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load data.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data!;
        return Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              NotesScreen(
                client: widget.client,
                onLoggedOut: widget.onLoggedOut,
                data: data,
                usingCache: _usingCache,
                onRefresh: _refresh,
                isActive: _selectedIndex == 0,
              ),
              TasksScreen(
                data: data,
                client: widget.client,
                onLoggedOut: widget.onLoggedOut,
                onRefresh: _refresh,
                usingCache: _usingCache,
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.sticky_note_2_outlined),
                selectedIcon: Icon(Icons.sticky_note_2),
                label: 'Notes',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_circle_outline),
                selectedIcon: Icon(Icons.check_circle),
                label: 'Tasks',
              ),
            ],
          ),
        );
      },
    );
  }
}
