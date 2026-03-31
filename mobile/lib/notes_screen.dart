import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'backend.dart';
import 'add_note_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _dataFuture = widget.client.getDashboardData();
  }

  void _refresh() {
    setState(() {
      _dataFuture = widget.client.getDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        forceMaterialTransparency: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/cony.webp', height: 32, width: 32),
            const SizedBox(width: 8),
            const Text('Sophie Notes'),
          ],
        ),
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

          if (notes.isEmpty) {
            return const Center(child: Text('No notes yet.'));
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = notes[index];
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
                  child: MarkdownBody(
                    data: _preserveBlankLines(note.text),
                    softLineBreak: true,
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
            if (note.alerts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: note.alerts
                    .map(
                      (a) => _Chip(
                        icon: Icons.alarm,
                        label: _formatAlertTime(a.time),
                        color: theme.colorScheme.errorContainer,
                        textColor: theme.colorScheme.onErrorContainer,
                      ),
                    )
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

  String _formatAlertTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return isoTime;
    }
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
