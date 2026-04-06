import 'package:flutter/material.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/screens/add_note_screen.dart';
import 'package:sophie/storage.dart';
import 'package:sophie/widgets/note_card.dart';

class NotesScreen extends StatefulWidget {
  final BackendClient client;
  final VoidCallback onLoggedOut;

  const NotesScreen({
    super.key,
    required this.client,
    required this.onLoggedOut,
  });

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();

  late Future<DashboardData> _dataFuture;
  bool _usingCache = false;
  String? _selectedTag;

  // Matches #tag (word chars directly after #, no space — distinguishes from markdown headings)
  final _tagRegex = RegExp(
    r'(?<!\S)#([\p{L}\p{N}_]+)',
    multiLine: true,
    unicode: true,
  );

  List<String> _extractTags(String text) {
    return _tagRegex
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toList();
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

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _usingCache = false;
      _dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: FutureBuilder<DashboardData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          final allTags = <String>{};
          if (snapshot.hasData) {
            for (final note in snapshot.data!.notes) {
              allTags.addAll(_extractTags(note.text));
            }
          }
          final sorted = allTags.toList()..sort();
          return Drawer(
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Tags',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (sorted.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('No tags found.'),
                    )
                  else
                    Expanded(
                      child: ListView(
                        children: [
                          if (_selectedTag != null)
                            ListTile(
                              leading: const Icon(Icons.clear),
                              title: const Text('Clear filter'),
                              onTap: () {
                                setState(() => _selectedTag = null);
                                Navigator.of(context).pop();
                              },
                            ),
                          ...sorted.map(
                            (tag) => ListTile(
                              leading: const Icon(Icons.tag),
                              title: Text('#$tag'),
                              selected: _selectedTag == tag,
                              onTap: () {
                                setState(() => _selectedTag = tag);
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedTag != null)
              Flexible(
                child: Text(
                  'Sophie Notes  •  #$_selectedTag',
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              )
            else
              const Text('Sophie Notes'),
          ],
        ),
        actions: [
          if (_usingCache)
            Tooltip(
              message: 'Showing cached data — could not reach server',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.warning_amber_rounded, color: Colors.orange),
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
              if (confirmed == true) widget.onLoggedOut();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final DashboardData? data = await _dataFuture.then<DashboardData?>(
            (d) => d,
            onError: (_) => null,
          );
          if (!context.mounted) return;
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddNoteScreen(
                client: widget.client,
                users: data?.users ?? const [],
              ),
            ),
          );
          if (created == true) _refresh();
        },
        tooltip: 'Add note',
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<DashboardData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load notes.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final notes = snapshot.data!.notes;
          final filtered = _selectedTag == null
              ? notes
              : notes
                    .where((n) => _extractTags(n.text).contains(_selectedTag))
                    .toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(
                _selectedTag != null
                    ? 'No notes tagged #$_selectedTag.'
                    : 'No notes yet.',
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = filtered[index];
                return NoteCard(
                  note: note,
                  users: snapshot.data!.users,
                  client: widget.client,
                  onEdited: _refresh,
                  scrollController: _scrollController,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
