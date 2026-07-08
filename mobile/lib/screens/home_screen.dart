import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/screens/notes_screen.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/screens/tasks_screen.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/services/user_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onLoggedOut;

  const HomeScreen({super.key, required this.onLoggedOut});

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
  AppEventSubscription? _appEventSub;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    _appEventSub = AppEventBus.instance.listen(_handleAppEvent);
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
    _appEventSub?.cancel();
    _refreshSub?.cancel();
    super.dispose();
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

  Future _handleAppEvent(AppEvent event) async {
    switch (event) {
      case AppLogoutEvent():
        widget.onLoggedOut();
        break;
      case AppSyncEvent():
        _refresh();
        break;
    }
  }

  Future<DashboardData> _loadData() async {
    DashboardData? data;
    try {
      data = await getIt<BackendClient>().getDashboardData();
      await AlertNotifications.rescheduleAll(data.tasks);
      await Storage.saveDashboardData(data);
      if (Platform.isAndroid) {
        await _pushTasksToWidget(data.tasks);
      }

      if (mounted) setState(() => _usingCache = false);
      return data;
    } catch (error) {
      data = Storage.getDashboardData();
      if (data != null) {
        if (mounted) setState(() => _usingCache = true);
        return data;
      }
      rethrow;
    } finally {
      if (data != null) {
        if (getIt.isRegistered(type: UserService)) {
          getIt.releaseInstance(getIt<UserService>());
        }
        getIt.registerSingleton(
          UserService(currentUserId: data.user.id, users: data.users),
        );
      }
    }
  }

  void _refresh() {
    setState(() {
      _usingCache = false;
      _dataFuture = _loadData();
    });
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
              NotesScreen(notes: data.notes, usingCache: _usingCache),
              TasksScreen(tasks: data.tasks, usingCache: _usingCache),
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
