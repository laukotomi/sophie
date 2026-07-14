import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sophie/events/note_deleted_event.dart';
import 'package:sophie/events/note_file_deleted_event.dart';
import 'package:sophie/events/note_saved_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/app_user.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/models/note_file.dart';
import 'package:sophie/models/note_history_entry.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/services/note_events.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/screens/add_collaborator_screen.dart';
import 'package:sophie/services/markdown_text_controller.dart';
import 'package:sophie/services/user_service.dart';
import 'package:sophie/utils/note_colors.dart';
import 'package:sophie/dialogs/delete_file_dialog.dart';
import 'package:sophie/dialogs/discard_dialog.dart';
import 'package:sophie/widgets/note_history_sheet.dart';
import 'package:sophie/dialogs/note_settings_dialog.dart';
import 'package:sophie/dialogs/type_to_confirm_dialog.dart';

class AddNoteScreen extends StatefulWidget {
  // When non-null the screen is in edit mode
  final Note? existingNote;
  // True when the note was opened without a server lock (no connectivity).
  final bool offlineMode;

  const AddNoteScreen({
    super.key,
    required this.offlineMode,
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
  bool _loadingHistory = false;
  Timer? _lockHeartbeat;
  int? _fixedPosition;
  String? _color;
  bool _dontFold = false;
  bool _todoList = false;
  String? _errorMessage;

  bool get _isEditing => widget.existingNote != null;

  bool get _hasChanges {
    final originalText = widget.existingNote?.text ?? '';
    return _textController.text.trim() != originalText.trim();
  }

  @override
  void initState() {
    super.initState();

    _fixedPosition = widget.existingNote?.position;
    _color = widget.existingNote?.color;
    _dontFold = widget.existingNote?.dontFold ?? false;
    _todoList = widget.existingNote?.todoList ?? false;
    _existingFiles = List.of(widget.existingNote?.files ?? []);

    // Pre-populate collaborators from the existing note, matching against users
    final users = getIt<UserService>().users;
    _collaborators =
        widget.existingNote?.collaborators
            .map((c) {
              final user = users.where((u) => u.id == c.id).firstOrNull;
              if (user == null) return null;
              return (user, c.right);
            })
            .whereType<(AppUser, String)>()
            .toList() ??
        [];
    _textController = MarkdownTextController(
      text: widget.existingNote?.text ?? '',
    );

    if (_isEditing) WidgetsBinding.instance.addObserver(this);

    if (_isEditing && !widget.offlineMode) {
      _startLockHeartbeat();
    }
  }

  @override
  void dispose() {
    if (_isEditing) WidgetsBinding.instance.removeObserver(this);
    _lockHeartbeat?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future _deleteExistingFile(NoteFile file) async {
    final confirmed = await showDeleteFileDialog(context, file.fileName);
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      if (file.id != null) {
        final event = NoteFileDeletedEvent(fileId: file.id!);
        await NoteEventBus.instance.emit(event);
      }
      if (mounted) setState(() => _existingFiles.remove(file));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to delete file')),
      );
    }
  }

  Future _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => NoteSettingsDialog(
        initialPosition: _fixedPosition,
        initialColor: _color,
        initialDontFold: _dontFold,
        initialTodoList: _todoList,
        palette: kNotePalette,
        contrastColor: noteContrastColor,
        onApply: (position, color, dontFold, todoList) {
          setState(() {
            _fixedPosition = position;
            _color = color;
            _dontFold = dontFold;
            _todoList = todoList;
          });
        },
      ),
    );
  }

  Future _openAddCollaborator() async {
    final users = getIt<UserService>().users;
    final alreadyAdded = _collaborators.map((c) => c.$1.id).toSet();
    alreadyAdded.add(getIt<UserService>().currentUserId);
    if (widget.existingNote != null) {
      alreadyAdded.add(widget.existingNote!.ownerId);
    }
    final available = users.where((u) => !alreadyAdded.contains(u.id)).toList();

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

  Future _openAddFile() async {
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
        await getIt<BackendNote>().refreshNoteLock(widget.existingNote!.id);
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
      if (!widget.offlineMode) _startLockHeartbeat();
    }
  }

  Future _openHistory() async {
    setState(() => _loadingHistory = true);
    List<NoteHistoryEntry> history;
    try {
      history = await getIt<BackendNote>().getNoteHistory(
        widget.existingNote!.id,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _loadingHistory = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load version history.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loadingHistory = false);

    if (history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous versions found.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteHistorySheet(
        history: history,
        onLoad: (text) => _textController.text = text,
      ),
    );
  }

  Future _deleteNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const TypeToConfirmDialog(
        title: 'Delete note',
        message: 'This cannot be undone. Type "yes" to confirm.',
        confirmLabel: 'Delete',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await NoteEventBus.instance.emit(
        NoteDeletedEvent(widget.existingNote!.id),
      );
      if (mounted) Navigator.of(context).pop();
    } on UnauthorizedException {
      // handled by onUnauthorized
    } catch (_) {
      if (mounted) setState(() => _errorMessage = 'Failed to delete note.');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future _releaseEditLock() async {
    if (!_isEditing || widget.offlineMode) return;
    setState(() => _releasingLock = true);
    try {
      await getIt<BackendNote>().releaseNoteLock(widget.existingNote!.id);
    } catch (_) {
      // Ignore — lock will expire on its own.
    } finally {
      if (mounted) setState(() => _releasingLock = false);
    }
  }

  Future _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final event = NoteSavedEvent(
        collaborators: _collaborators
            .map((c) => (userId: c.$1.id, right: c.$2))
            .toList(),
        color: _color,
        dontFold: _dontFold,
        files: _pickedFiles.map((f) => (path: f.path!, name: f.name)).toList(),
        fixedPosition: _fixedPosition,
        noteId: _isEditing ? widget.existingNote!.id : null,
        text: _textController.text.trim(),
        todoList: _todoList,
      );
      await NoteEventBus.instance.emit(event);

      if (mounted) {
        Navigator.of(context).pop();
      }
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
        final confirmed = _hasChanges ? await showDiscardDialog(context) : true;
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
            if (_lockError || widget.offlineMode)
              Tooltip(
                message: widget.offlineMode
                    ? 'Offline — changes will sync when connected'
                    : 'Could not extend edit lock — will retry',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.cloud_off, color: Colors.orange),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Note settings',
              onPressed: _openSettings,
            ),
            PopupMenuButton<String>(
              icon: (_deleting || _loadingHistory)
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.more_vert),
              enabled: !_saving && !_deleting && !_loadingHistory,
              onSelected: (value) {
                if (value == 'collaborator') _openAddCollaborator();
                if (value == 'file') _openAddFile();
                if (value == 'history') _openHistory();
                if (value == 'delete') _deleteNote();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'collaborator',
                  child: ListTile(
                    leading: Icon(Icons.person_add),
                    title: Text('Add collaborator'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'file',
                  child: ListTile(
                    leading: Icon(Icons.attach_file),
                    title: Text('Add file'),
                  ),
                ),
                if (_isEditing)
                  const PopupMenuItem(
                    value: 'history',
                    child: ListTile(
                      leading: Icon(Icons.history),
                      title: Text('Version history'),
                    ),
                  ),
                if (_isEditing) const PopupMenuDivider(),
                if (_isEditing)
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Delete note',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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
