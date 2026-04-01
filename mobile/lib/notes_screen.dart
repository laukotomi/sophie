import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'backend.dart';
import 'add_note_screen.dart';

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
  late Future<DashboardData> _dataFuture;
  bool _usingCache = false;
  String? _selectedTag;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Future<DashboardData> _loadData() async {
    try {
      final data = await widget.client.getDashboardData();
      await DashboardCache.save(data);
      if (mounted) setState(() => _usingCache = false);
      return data;
    } catch (error) {
      final cached = await DashboardCache.load();
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
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = filtered[index];
                return _NoteCard(
                  note: note,
                  users: snapshot.data!.users,
                  client: widget.client,
                  onEdited: _refresh,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final List<AppUser> users;
  final BackendClient client;
  final VoidCallback onEdited;

  const _NoteCard({
    required this.note,
    required this.users,
    required this.client,
    required this.onEdited,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updatedAt = _formatDate(note.updatedAt);

    final canEdit = note.isOwner || note.right == 'edit';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectionArea(
                    child: MarkdownBody(
                      data: _preserveBlankLines(note.text),
                      softLineBreak: true,
                    ),
                  ),
                ),
                if (canEdit)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit note',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final edited = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => AddNoteScreen(
                            client: client,
                            users: users,
                            existingNote: note,
                          ),
                        ),
                      );
                      if (edited == true) onEdited();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (note.isOwner)
                      _Chip(
                        icon: Icons.edit,
                        label: 'Owner',
                        color: theme.colorScheme.primaryContainer,
                        textColor: theme.colorScheme.onPrimaryContainer,
                      )
                    else
                      _Chip(
                        icon: note.right == 'edit'
                            ? Icons.edit
                            : Icons.visibility,
                        label: note.right == 'edit' ? 'Can edit' : 'View only',
                        color: theme.colorScheme.secondaryContainer,
                        textColor: theme.colorScheme.onSecondaryContainer,
                      ),
                    ...note.collaborators.map(
                      (c) => _Chip(
                        icon: Icons.person,
                        label: c.name,
                        color: theme.colorScheme.tertiaryContainer,
                        textColor: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  updatedAt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (note.files.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: note.files
                    .map((f) => _FileDownloadChip(file: f, client: client))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  // Replaces runs of extra blank lines with non-breaking space paragraphs so
  // the user's intentional vertical spacing is preserved when rendered as Markdown.
  String _preserveBlankLines(String text) {
    return text.replaceAllMapped(RegExp(r'\n{2,}'), (match) {
      final extraBlanks = match[0]!.length - 1;
      final spacers = List.filled(extraBlanks, '\u00A0').join('\n\n');
      return '\n\n$spacers\n\n';
    });
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _FileDownloadChip extends StatefulWidget {
  final NoteFile file;
  final BackendClient client;

  const _FileDownloadChip({required this.file, required this.client});

  @override
  State<_FileDownloadChip> createState() => _FileDownloadChipState();
}

class _FileDownloadChipState extends State<_FileDownloadChip> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.client.downloadFile(widget.file.id);
      final tempPath = '${Directory.systemTemp.path}/${widget.file.fileName}';
      await File(tempPath).writeAsBytes(bytes);
      await OpenFilex.open(tempPath);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to download file')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 14,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 4),
          Text(
            widget.file.fileName,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(width: 4),
          _downloading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.onSurface,
                  ),
                )
              : GestureDetector(
                  onTap: _download,
                  child: Icon(
                    Icons.download_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: textColor)),
        ],
      ),
    );
  }
}
