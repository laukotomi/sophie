import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/screens/add_task_screen.dart';
import 'package:sophie/widgets/task_card.dart';
import 'package:table_calendar/table_calendar.dart';

class TasksScreen extends StatefulWidget {
  final DashboardData data;
  final BackendClient client;
  final VoidCallback onLoggedOut;
  final Future<void> Function() onRefresh;

  const TasksScreen({
    super.key,
    required this.data,
    required this.client,
    required this.onLoggedOut,
    required this.onRefresh,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Set<DateTime> get _daysWithTasks => widget.data.tasks
      .where((t) => t.dueAt != null)
      .map((t) => DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day))
      .toSet();

  List<Task> get _filteredTasks {
    if (_selectedDay == null) return widget.data.tasks;
    return widget.data.tasks
        .where(
          (t) =>
              t.dueAt != null &&
              isSameDay(t.dueAt!, _selectedDay!),
        )
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
                    _selectedDay = isSameDay(selectedDay, _selectedDay ?? DateTime(0))
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
                  final normalized =
                      DateTime(day.year, day.month, day.day);
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
            ? Text(
                'Tasks  •  ${DateFormat('MMM d').format(_selectedDay!)}',
              )
            : const Text('Sophie Tasks'),
        actions: [
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
              if (confirmed == true) widget.onLoggedOut();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_tasks',
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTaskScreen(
                users: widget.data.users,
                currentUserId: widget.data.user.id,
                client: widget.client,
              ),
            ),
          );
          if (created == true) widget.onRefresh();
        },
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
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
                    child: TaskCard(
                      task: task,
                      client: widget.client,
                      onChanged: widget.onRefresh,
                      allUsers: widget.data.users,
                      currentUserId: widget.data.user.id,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
