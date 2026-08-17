import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sophie/events/app_check_for_changes_event.dart';
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/events/app_data_change_event.dart';
import 'package:sophie/events/app_offline_mode_changed_event.dart';
import 'package:sophie/events/app_sync_conflict_event.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/events/note_sync_event.dart';
import 'package:sophie/events/task_sync_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/screens/snooze_picker_screen.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/screens/notes_screen.dart';
import 'package:sophie/screens/settings_screen.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/screens/tasks_screen.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/services/user_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onLoggedOut;
  final bool offlineMode;

  const HomeScreen({
    super.key,
    required this.onLoggedOut,
    required this.offlineMode,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _navChannel = MethodChannel('sophie/navigation');
  static const _navEvents = EventChannel('sophie/navigation/events');

  int _selectedIndex = 0;
  late Future<DashboardData> _dataFuture;
  DashboardData? _currentData;
  bool _usingCache = false;
  StreamSubscription? _navEventSub;
  AppEventSubscription? _appEventSub;
  DateTime? _lastCheckForChanges;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    _appEventSub = AppEventBus.instance.listen(_handleAppEvent);
    if (!kIsWeb && Platform.isAndroid) {
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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _navEventSub?.cancel();
    _appEventSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      if (widget.offlineMode) return;

      if (!_usingCache &&
          (_lastCheckForChanges == null ||
              DateTime.now().difference(_lastCheckForChanges!) >
                  const Duration(minutes: 1))) {
        try {
          _lastCheckForChanges = DateTime.now();
          await AppEventBus.instance.emit(AppCheckForChangesEvent.start());
          final data = await getIt<BackendClient>().getDashboardData();
          await Storage.saveDashboardData(data);
          await AppEventBus.instance.emit(AppCheckForChangesEvent.result(data));
        } catch (e) {
          await AppEventBus.instance.emit(AppCheckForChangesEvent.result(null));
        }
      }
    }
  }

  Future _handleAppEvent(AppEvent event) async {
    switch (event) {
      case AppLogoutEvent():
        widget.onLoggedOut();
        break;
      case AppDataChangeEvent():
        await Storage.saveDashboardData(_currentData!);
        break;
      case AppOfflineModeChangedEvent():
        setState(() => _usingCache = event.offlineMode);
        break;
      case AppSyncConflictEvent():
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
        break;
      case AppSyncEvent():
        setState(() {
          _usingCache = false;
          _dataFuture = () async {
            final data = await _loadData();
            if (!_usingCache && !kIsWeb) {
              await AlertNotifications.refreshNotifications(data.tasks);
            }
            return data;
          }();
        });
        break;
    }
  }

  Future<DashboardData> _loadData() async {
    DashboardData? data;
    try {
      if (!widget.offlineMode) {
        await AppEventBus.instance.emit(NoteSyncEvent());
        await AppEventBus.instance.emit(TaskSyncEvent());

        data = await getIt<BackendClient>().getDashboardData();
        await Storage.saveDashboardData(data);
      } else {
        data = Storage.getDashboardData()!;
      }

      if (mounted) setState(() => _usingCache = false);
      _currentData = data;
      return data;
    } catch (error) {
      data = Storage.getDashboardData();
      if (data != null) {
        if (mounted) setState(() => _usingCache = true);
        _currentData = data;
        return data;
      }
      rethrow; // this should not really happen as once logic was successful dashboard data is saved to storage immediately
    } finally {
      if (data != null) {
        if (getIt.isRegistered(type: UserService)) {
          getIt.releaseInstance(getIt<UserService>());
        }
        getIt.registerSingleton(
          UserService(currentUserId: data.user.id, users: data.users),
        );
      }

      final snooze = Storage.tryGetPendingSnooze();
      if (snooze != null) {
        await navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => SnoozePickerScreen(
              alarmId: snooze.alarmId,
              taskId: snooze.taskId,
              body: snooze.body,
            ),
          ),
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
              NotesScreen(
                notes: data.notes,
                offlineMode: widget.offlineMode,
                usingCache: _usingCache,
                isActive: _selectedIndex == 0,
              ),
              TasksScreen(
                tasks: data.tasks,
                offlineMode: widget.offlineMode,
                usingCache: _usingCache,
              ),
              SettingsScreen(
                tasks: data.tasks,
                offlineMode: widget.offlineMode,
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            height: 64,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
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
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}
