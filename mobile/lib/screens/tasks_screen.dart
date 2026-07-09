import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/events/task_deleted_event.dart';
import 'package:sophie/events/task_saved_event.dart';
import 'package:sophie/events/task_sync_event.dart';
import 'package:sophie/events/task_toggle_done_event.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/screens/add_task_screen.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/services/task_events.dart';
import 'package:sophie/widgets/task_card.dart';
import 'package:table_calendar/table_calendar.dart';

class TasksScreen extends StatefulWidget {
  final List<Task> tasks;
  final bool usingCache;

  const TasksScreen({super.key, required this.tasks, this.usingCache = false});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final StreamSubscription<void>? _snoozeQueueSub;
  late final StreamSubscription<TaskEvent>? _taskEventSub;
  late final AppEventSubscription? _appEventSub;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _taskEventSub = TaskEventBus.instance.stream.listen(_handleTaskEvent);
    _appEventSub = AppEventBus.instance.listen((event) async {
      if (event is TaskSyncEvent) {
        await _syncTaskChanges();
      }
    });
  }

  @override
  void dispose() {
    _snoozeQueueSub?.cancel();
    _taskEventSub?.cancel();
    _appEventSub?.cancel();
    super.dispose();
  }

  Future _syncTaskChanges() async {}

  void _handleTaskEvent(TaskEvent event) {
    if (!widget.usingCache) return;

    Storage.addTaskEvent(event);

    if (event is TaskDeletedEvent) {
      widget.tasks.removeWhere((t) => t.id == event.taskId);
    } else if (event is TaskSavedEvent) {
      if (!event.isNew) {
        final task = widget.tasks.firstWhere((t) => t.id == event.taskId);
        setState(() {
          task
            ..alerts = event.alerts
            ..collaborators = event.collaboratorIds
            ..color = event.color
            ..dueAt = event.dueAt
            ..rrule = event.rrule
            ..text = event.text;
        });
      } else {
        setState(() {
          widget.tasks.add(
            Task(
              id: event.taskId,
              text: event.text,
              rrule: event.rrule,
              color: event.color,
              dueAt: event.dueAt,
              doneAt: null,
              createdAt: DateTime.now(),
              isOwner: true,
              collaborators: event.collaboratorIds,
              alerts: event.alerts,
            ),
          );
        });
      }

      widget.tasks.sort((a, b) {
        if (a.doneAt != null && b.doneAt == null) return 1;
        if (a.doneAt == null && b.doneAt != null) return -1;
        if (a.dueAt == null && b.dueAt != null) return -1;
        if (a.dueAt != null && b.dueAt == null) return 1;
        if (a.dueAt != null && b.dueAt != null) {
          final dueDiff = a.dueAt!.compareTo(b.dueAt!);
          if (dueDiff != 0) return dueDiff;
        }
        return b.createdAt.compareTo(a.createdAt);
      });
    } else if (event is TaskToggleDoneEvent) {
      final task = widget.tasks.firstWhere((t) => t.id == event.taskId);
      setState(() {
        task.doneAt = task.doneAt == null ? DateTime.now() : null;
      });
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
          if (widget.usingCache)
            Tooltip(
              message: 'Showing cached data — could not reach server',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.cloud_off, color: Colors.orange),
              ),
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
                AppEventBus.instance.emit(AppLogoutEvent());
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
          AppEventBus.instance.emit(AppSyncEvent());
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
