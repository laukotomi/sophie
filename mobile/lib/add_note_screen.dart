import 'package:flutter/material.dart';
import 'backend.dart';
import 'add_collaborator_screen.dart';
import 'add_alert_screen.dart';

// Matches numbered list prefixes: "1. ", "12. ", etc. — captures the number separately.
final _numberedPattern = RegExp(r'^(\s*)(\d+)(\.)\s+');
// Matches bullet/blockquote prefixes: "- ", "* ", "> "
final _bulletPattern = RegExp(r'^(\s*(?:[-*>])\s+)');

String? _nextPrefix(String line) {
  final numMatch = _numberedPattern.firstMatch(line);
  if (numMatch != null) {
    final indent = numMatch.group(1)!;
    final n = int.parse(numMatch.group(2)!);
    final dot = numMatch.group(3)!;
    return '$indent${n + 1}$dot ';
  }
  final bulletMatch = _bulletPattern.firstMatch(line);
  if (bulletMatch != null) return bulletMatch.group(1)!;
  return null;
}

class _MarkdownTextController extends TextEditingController {
  _MarkdownTextController({super.text});

  @override
  set value(TextEditingValue newValue) {
    final old = this.value;
    // Detect a newline being inserted
    if (newValue.text.length == old.text.length + 1 &&
        newValue.text[newValue.selection.baseOffset - 1] == '\n') {
      final cursor = newValue.selection.baseOffset;
      final textBefore = newValue.text.substring(0, cursor);
      final lineStart = textBefore.lastIndexOf('\n', cursor - 2) + 1;
      final prevLine = textBefore.substring(lineStart, cursor - 1);
      final prefix = _nextPrefix(prevLine);
      if (prefix != null) {
        // If the previous line had only the prefix (empty item), remove it instead
        final matchLen =
            (_numberedPattern.firstMatch(prevLine) ??
                    _bulletPattern.firstMatch(prevLine))!
                .group(0)!
                .length;
        final isEmpty = prevLine.length == matchLen;
        if (isEmpty) {
          final cleaned =
              old.text.substring(0, lineStart) + old.text.substring(cursor - 1);
          super.value = TextEditingValue(
            text: cleaned,
            selection: TextSelection.collapsed(offset: lineStart),
          );
          return;
        }
        final inserted =
            newValue.text.substring(0, cursor) +
            prefix +
            newValue.text.substring(cursor);
        super.value = TextEditingValue(
          text: inserted,
          selection: TextSelection.collapsed(offset: cursor + prefix.length),
        );
        return;
      }
    }
    super.value = newValue;
  }
}

class AddNoteScreen extends StatefulWidget {
  final BackendClient client;
  final List<AppUser> users;
  // When non-null the screen is in edit mode
  final Note? existingNote;

  const AddNoteScreen({
    super.key,
    required this.client,
    required this.users,
    this.existingNote,
  });

  @override
  State<AddNoteScreen> createState() => _AddNoteScreenState();
}

class _AddNoteScreenState extends State<AddNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _textController;

  // Each entry is (user, right)
  late final List<(AppUser, String)> _collaborators;

  bool _saving = false;
  bool _deleting = false;
  int? _fixedPosition;
  String? _errorMessage;

  bool get _isEditing => widget.existingNote != null;

  bool get _hasChanges {
    final originalText = widget.existingNote?.text ?? '';
    return _textController.text.trim() != originalText.trim();
  }

  @override
  void initState() {
    super.initState();
    _textController = _MarkdownTextController(
      text: widget.existingNote?.text ?? '',
    );
    // Pre-populate collaborators from the existing note, matching against users
    _collaborators =
        widget.existingNote?.collaborators
            .map((c) {
              final user = widget.users.where((u) => u.id == c.id).firstOrNull;
              if (user == null) return null;
              return (user, c.right);
            })
            .whereType<(AppUser, String)>()
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    final controller = TextEditingController(
      text: _fixedPosition?.toString() ?? '',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note settings'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Fixed position',
            hintText: 'Leave empty for automatic',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final raw = controller.text.trim();
              setState(() {
                _fixedPosition = raw.isEmpty ? null : int.tryParse(raw);
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _openAddCollaborator() async {
    final alreadyAdded = _collaborators.map((c) => c.$1.id).toSet();
    if (widget.existingNote != null) {
      alreadyAdded.add(widget.existingNote!.ownerId);
    }
    final available = widget.users
        .where((u) => !alreadyAdded.contains(u.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All users have already been added.')),
      );
      return;
    }

    final result = await Navigator.of(context).push<(AppUser, String)>(
      MaterialPageRoute(
        builder: (_) => AddCollaboratorScreen(users: available),
      ),
    );

    if (result != null) {
      setState(() => _collaborators.add(result));
    }
  }

  Future<void> _openAddAlert() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AddAlertScreen()));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final collabs = _collaborators
        .map((c) => (userId: c.$1.id, right: c.$2))
        .toList();

    try {
      if (_isEditing) {
        await widget.client.updateNote(
          widget.existingNote!.id,
          _textController.text.trim(),
          collaborators: collabs,
          fixedPosition: _fixedPosition,
        );
      } else {
        await widget.client.createNote(
          _textController.text.trim(),
          collaborators: collabs,
          fixedPosition: _fixedPosition,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on UnauthorizedException {
      // onUnauthorized callback already handles logout
    } catch (_) {
      setState(() => _errorMessage = 'Failed to save note. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_hasChanges) {
          Navigator.of(context).pop();
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your changes will be lost.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Note' : 'New Note'),
          actions: [
            if (_isEditing)
              IconButton(
                icon: _deleting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                tooltip: 'Delete note',
                onPressed: (_saving || _deleting)
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete note'),
                            content: const Text(
                              'This cannot be undone. Are you sure?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !mounted) return;
                        setState(() => _deleting = true);
                        try {
                          await widget.client.deleteNote(
                            widget.existingNote!.id,
                          );
                          if (mounted) Navigator.of(context).pop(true);
                        } on UnauthorizedException {
                          // handled by onUnauthorized
                        } catch (_) {
                          setState(
                            () => _errorMessage = 'Failed to delete note.',
                          );
                        } finally {
                          if (mounted) setState(() => _deleting = false);
                        }
                      },
              ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Note settings',
              onPressed: _openSettings,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.add),
              onSelected: (value) {
                if (value == 'collaborator') _openAddCollaborator();
                if (value == 'alert') _openAddAlert();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'collaborator',
                  child: ListTile(
                    leading: Icon(Icons.person_add),
                    title: Text('Add collaborator'),
                  ),
                ),
                PopupMenuItem(
                  value: 'alert',
                  child: ListTile(
                    leading: Icon(Icons.alarm_add),
                    title: Text('Add alert'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Write your note here…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Note cannot be empty.';
                      }
                      return null;
                    },
                  ),
                ),
                if (_collaborators.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Collaborators:',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      ..._collaborators.map(
                        (c) => Chip(
                          avatar: Icon(
                            c.$2 == 'edit' ? Icons.edit : Icons.visibility,
                            size: 16,
                          ),
                          label: Text(c.$1.name),
                          onDeleted: () =>
                              setState(() => _collaborators.remove(c)),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ), // Scaffold
    ); // PopScope
  }
}
