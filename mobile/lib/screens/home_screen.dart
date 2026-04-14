import 'package:flutter/material.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/screens/notes_screen.dart';
import 'package:sophie/screens/tasks_screen.dart';
import 'package:sophie/storage.dart';

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
  int _selectedIndex = 0;
  late Future<DashboardData> _dataFuture;
  bool _usingCache = false;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<DashboardData> _loadData() async {
    try {
      final data = await widget.client.getDashboardData();
      await Storage.saveDashboardData(data);
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
                onRefresh: () async => _refresh(),
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
