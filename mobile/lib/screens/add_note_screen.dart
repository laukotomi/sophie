import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/screens/add_collaborator_screen.dart';
import 'package:sophie/services/markdown_text_controller.dart';
import 'package:sophie/utils/note_colors.dart';
import 'package:sophie/widgets/note_settings_dialog.dart';

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

class _AddNoteScreenState extends State<AddNoteScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _textController;

  // Each entry is (user, right)
  late final List<(AppUser, String)> _collaborators;
  final List<PlatformFile> _pickedFiles = [];
  late final List<NoteFile> _existingFiles;

  bool _saving = false;
  bool _deleting = false;
  bool _releasingLock = false;
  bool _lockError = false;
  Timer? _lockHeartbeat;
  int? _fixedPosition;
  String? _color;
  String? _errorMessage;

  bool get _isEditing => widget.existingNote != null;

  bool get _hasChanges {
    final originalText = widget.existingNote?.text ?? '';
    return _textController.text.trim() != originalText.trim();
  }

  @override
  void initState() {
    super.initState();
    if (_isEditing) WidgetsBinding.instance.addObserver(this);
    _textController = MarkdownTextController(
      text: widget.existingNote?.text ?? '',
    );
    _fixedPosition = widget.existingNote?.position;
    _color = widget.existingNote?.color;
    _existingFiles = List.of(widget.existingNote?.files ?? []);
    if (_isEditing) _startLockHeartbeat();
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
    if (_isEditing) WidgetsBinding.instance.removeObserver(this);
    _lockHeartbeat?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _deleteExistingFile(NoteFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content: Text(
          'Are you sure you want to delete "${file.fileName}"? This cannot be undone.',
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

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.client.deleteFile(file.id);
      if (mounted) setState(() => _existingFiles.remove(file));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to delete file')),
      );
    }
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => NoteSettingsDialog(
        initialPosition: _fixedPosition,
        initialColor: _color,
        palette: kNotePalette,
        contrastColor: noteContrastColor,
        onApply: (position, color) {
          setState(() {
            _fixedPosition = position;
            _color = color;
          });
        },
      ),
    );
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

  Future<void> _openAddFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    final newFiles = result.files.where((f) => f.path != null);
    if (!mounted) return;
    setState(() {
      for (final f in newFiles) {
        if (!_pickedFiles.any((e) => e.path == f.path)) {
          _pickedFiles.add(f);
        }
      }
    });
  }

  void _startLockHeartbeat() {
    _lockHeartbeat = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        await widget.client.refreshNoteLock(widget.existingNote!.id);
        if (mounted && _lockError) setState(() => _lockError = false);
      } catch (_) {
        if (mounted && !_lockError) setState(() => _lockError = true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isEditing) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lockHeartbeat?.cancel();
      _lockHeartbeat = null;
    } else if (state == AppLifecycleState.resumed && _lockHeartbeat == null) {
      _startLockHeartbeat();
    }
  }

  Future<void> _releaseEditLock() async {
    if (!_isEditing) return;
    setState(() => _releasingLock = true);
    try {
      await widget.client.releaseNoteLock(widget.existingNote!.id);
    } catch (_) {
      // Ignore — lock will expire on its own.
    } finally {
      if (mounted) setState(() => _releasingLock = false);
    }
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

    final fileArgs = _pickedFiles
        .map((f) => (path: f.path!, name: f.name))
        .toList();

    try {
      if (_isEditing) {
        await widget.client.updateNote(
          widget.existingNote!.id,
          _textController.text.trim(),
          collaborators: collabs,
          fixedPosition: _fixedPosition,
          color: _color,
          files: fileArgs,
        );
      } else {
        await widget.client.createNote(
          _textController.text.trim(),
          collaborators: collabs,
          fixedPosition: _fixedPosition,
          color: _color,
          files: fileArgs,
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
          await _releaseEditLock();
          if (context.mounted) Navigator.of(context).pop();
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
        if (confirmed == true && context.mounted) {
          await _releaseEditLock();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit Note' : 'New Note'),
          bottom: _releasingLock
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(4),
                  child: LinearProgressIndicator(),
                )
              : null,
          actions: [
            if (_lockError)
              const Tooltip(
                message: 'Could not extend edit lock — will retry',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                ),
              ),
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
                          builder: (ctx) {
                            final confirmController = TextEditingController();
                            return StatefulBuilder(
                              builder: (ctx, setState) => AlertDialog(
                                title: const Text('Delete note'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'This cannot be undone. Type "yes" to confirm.',
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: confirmController,
                                      autofocus: true,
                                      decoration: const InputDecoration(
                                        hintText: 'yes',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed:
                                        confirmController.text
                                                .trim()
                                                .toLowerCase() ==
                                            'yes'
                                        ? () => Navigator.of(ctx).pop(true)
                                        : null,
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                        if (confirmed != true || !mounted) return;
                        setState(() => _deleting = true);
                        try {
                          await widget.client.deleteNote(
                            widget.existingNote!.id,
                          );
                          if (context.mounted) Navigator.of(context).pop(true);
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
                if (value == 'file') _openAddFile();
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
                  value: 'file',
                  child: ListTile(
                    leading: Icon(Icons.attach_file),
                    title: Text('Add file'),
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
                if (_existingFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Attached files:',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      ..._existingFiles.map(
                        (f) => Chip(
                          avatar: const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 16,
                          ),
                          label: Text(f.fileName),
                          onDeleted: () => _deleteExistingFile(f),
                        ),
                      ),
                    ],
                  ),
                ],
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
                if (_pickedFiles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Files:',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      ..._pickedFiles.map(
                        (f) => Chip(
                          avatar: const Icon(Icons.insert_drive_file, size: 16),
                          label: Text(f.name),
                          onDeleted: () =>
                              setState(() => _pickedFiles.remove(f)),
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
