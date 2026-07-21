import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/events/app_data_change_event.dart';
import 'package:sophie/events/app_offline_mode_changed_event.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/events/task_sync_event.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/screens/add_task_screen.dart';
import 'package:sophie/screens/alert_manager_screen.dart';
import 'package:sophie/screens/event_manager_screen.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/services/base_event.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/services/task_events.dart';
import 'package:sophie/widgets/task_card.dart';
import 'package:table_calendar/table_calendar.dart';

class TasksScreen extends StatefulWidget {
  final List<Task> tasks;
  final bool usingCache;

  const TasksScreen({super.key, required this.tasks, required this.usingCache});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final EventSubscription<TaskEvent> _taskEventSub;
  late final AppEventSubscription _appEventSub;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  int _pendingSyncs = 0;

  @override
  void initState() {
    super.initState();
    _taskEventSub = TaskEventBus.instance.listen(_handleTaskEvent);
    _appEventSub = AppEventBus.instance.listen((event) async {
      if (event is TaskSyncEvent) {
        await _syncTaskChanges();
      }
    });
  }

  @override
  void dispose() {
    _taskEventSub.cancel();
    _appEventSub.cancel();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future _syncTaskChanges() async {
    try {
      final events = Storage.getOfflineTaskEvents();
      if (events.isEmpty) return;

      for (final event in events) {
        try {
          if (!event.synced) {
            await event.sync(widget.tasks, _safeSetState);
            event.synced = true;
          }
          await Storage.removeTaskEvent(event.eventId);
        } on UnauthorizedException {
          await Storage.removeTaskEvent(event.eventId);
        } on NotFoundException {
          await Storage.removeTaskEvent(event.eventId);
        }
      }
    } catch (e) {
      await _handleSyncError(e);
      rethrow;
    }
  }

  Future _handleSyncError(Object e) async {
    await AppEventBus.instance.emit(
      AppOfflineModeChangedEvent(offlineMode: true),
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error syncing task changes: $e')));
    }
  }

  Future _handleTaskEvent(TaskEvent event) async {
    if (!event.applied) {
      await event.apply(widget.tasks, _safeSetState);
      event.applied = true;

      await AppEventBus.instance.emit(AppDataChangeEvent());
    }

    if (widget.usingCache) {
      await Storage.addOrUpdateTaskEvent(event);
    } else {
      _safeSetState(() => _pendingSyncs++);
      unawaited(_syncEventInBackground(event));
    }

    if (Platform.isAndroid) {
      await _pushTasksToWidget(widget.tasks);
    }
  }

  Future _syncEventInBackground(TaskEvent event) async {
    try {
      if (!event.synced) {
        await event.sync(widget.tasks, _safeSetState);
        event.synced = true;
      }
      await Storage.removeTaskEvent(event.eventId);
    } catch (e) {
      await Storage.addOrUpdateTaskEvent(event);
      await _handleSyncError(e);
    } finally {
      _safeSetState(() => _pendingSyncs--);
    }
  }

  Set<DateTime> get _daysWithTasks => widget.tasks
      .where((t) => t.dueAt != null)
      .map((t) => DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day))
      .toSet();

  List<Task> get _filteredTasks {
    if (_selectedDay == null) return widget.tasks;
    return widget.tasks
        .where((t) => t.dueAt != null && isSameDay(t.dueAt!, _selectedDay!))
        .toList();
  }

  static Future _pushTasksToWidget(List<Task> tasks) async {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final daysWithTasks = _daysWithTasks;
    final filteredTasks = _filteredTasks;
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Calendar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TableCalendar(
                firstDay: DateTime.utc(2000, 1, 1),
                lastDay: DateTime.utc(2100, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                selectedDayPredicate: (day) =>
                    _selectedDay != null && isSameDay(day, _selectedDay!),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay =
                        isSameDay(selectedDay, _selectedDay ?? DateTime(0))
                        ? null
                        : selectedDay;
                    _focusedDay = focusedDay;
                  });
                  Navigator.of(context).pop();
                },
                onPageChanged: (focusedDay) {
                  setState(() => _focusedDay = focusedDay);
                },
                eventLoader: (day) {
                  final normalized = DateTime(day.year, day.month, day.day);
                  return daysWithTasks.contains(normalized) ? [true] : [];
                },
                calendarStyle: CalendarStyle(
                  markerDecoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (_selectedDay != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear filter'),
                      onPressed: () {
                        setState(() => _selectedDay = null);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      appBar: AppBar(
        forceMaterialTransparency: true,
        leading: IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: 'Calendar',
          onPressed: () => _scaffoldKey.currentState!.openDrawer(),
        ),
        title: _selectedDay != null
            ? Text('Tasks  •  ${DateFormat('MMM d').format(_selectedDay!)}')
            : const Text('Sophie Tasks'),
        actions: [
          if (_pendingSyncs > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (widget.usingCache)
            Tooltip(
              message: 'Showing cached data — could not reach server',
              child: IconButton(
                icon: const Icon(Icons.cloud_off, color: Colors.orange),
                onPressed: () async {
                  final taskEvents = Storage.getOfflineTaskEvents();
                  final events = taskEvents
                      .map<BaseEvent>((event) => event)
                      .toList();
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => EventManagerScreen(
                        events: events,
                        onDeleteEvent: (event) =>
                            Storage.removeTaskEvent(event.eventId),
                      ),
                    ),
                  );
                },
              ),
            ),
          IconButton(
            icon: Icon(Icons.notifications_outlined),
            tooltip: 'Alert settings',
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const AlertManagerScreen()),
              );
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log out'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await AppEventBus.instance.emit(AppLogoutEvent());
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_tasks',
        onPressed: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTaskScreen(offlineMode: widget.usingCache),
            ),
          );
        },
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await AppEventBus.instance.emit(AppSyncEvent());
        },
        child: filteredTasks.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: Center(
                      child: Text(
                        _selectedDay != null
                            ? 'No tasks on ${DateFormat('MMM d').format(_selectedDay!)}.'
                            : 'No tasks yet.',
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: filteredTasks.length,
                itemBuilder: (context, i) {
                  final task = filteredTasks[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TaskCard(task: task, offlineMode: widget.usingCache),
                  );
                },
              ),
      ),
    );
  }
}
