import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/events/app_offline_data_change_event.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/events/note_deleted_event.dart';
import 'package:sophie/events/note_file_deleted_event.dart';
import 'package:sophie/events/note_saved_event.dart';
import 'package:sophie/events/note_sync_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/models/note_collaborator.dart';
import 'package:sophie/models/note_file.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/services/backend_note_file.dart';
import 'package:sophie/services/note_events.dart';
import 'package:sophie/screens/add_note_screen.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/services/user_service.dart';
import 'package:sophie/widgets/note_card.dart';

class NotesScreen extends StatefulWidget {
  final List<Note> notes;
  final bool usingCache;

  const NotesScreen({super.key, required this.notes, required this.usingCache});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  late final StreamSubscription<NoteEvent>? _noteEventSub;
  late final AppEventSubscription? _appEventSub;

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

  @override
  void initState() {
    super.initState();
    _noteEventSub = NoteEventBus.instance.stream.listen(_handleNoteEvent);
    _appEventSub = AppEventBus.instance.listen((event) async {
      if (event is NoteSyncEvent) {
        await _syncNoteChanges();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _noteEventSub?.cancel();
    _appEventSub?.cancel();
    super.dispose();
  }

  Future _syncNoteChanges() async {
    try {
      final events = await Storage.getOfflineNoteEvents();
      if (events.isEmpty) return;

      final noteClient = getIt<BackendNote>();

      for (final event in events) {
        try {
          if (event is NoteDeletedEvent) {
            await noteClient.deleteNote(event.noteId);
          } else if (event is NoteSavedEvent) {
            bool hadConflict = false;
            if (!event.isNew) {
              final result = await noteClient.acquireNoteLock(event.noteId);
              hadConflict = event.createdAt.isBefore(result.updatedAt);
            }
            await noteClient.saveNote(event);
            if (!event.isNew) {
              await noteClient.releaseNoteLock(event.noteId);
            }

            if (hadConflict) {
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
            }
          } else if (event is NoteFileDeletedEvent) {
            await getIt<BackendNoteFile>().deleteFile(event);
          }

          Storage.removeNoteEvent(event.eventId);
        } on UnauthorizedException {
          Storage.removeNoteEvent(event.eventId);
        } on NotFoundException {
          Storage.removeNoteEvent(event.eventId);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing note changes: $e')),
        );
      }
    }
  }

  void _handleNoteEvent(NoteEvent event) {
    if (!widget.usingCache) return;

    Storage.addNoteEvent(event);

    if (event is NoteSavedEvent) {
      final users = getIt<UserService>().users;
      final collabs = event.collaborators.map((c) {
        final user = users.firstWhere((u) => u.id == c.userId);
        return NoteCollaborator(
          id: user.id,
          email: user.email,
          name: user.name,
          right: c.right,
        );
      }).toList();

      final newFiles = event.files
          .map((f) => NoteFile(fileName: f.name))
          .toList();

      if (!event.isNew) {
        final note = widget.notes.firstWhere((n) => n.id == event.noteId);
        setState(() {
          note
            ..updatedAt = DateTime.now()
            ..position = event.fixedPosition
            ..text = event.text
            ..color = event.color
            ..dontFold = event.dontFold
            ..todoList = event.todoList
            ..collaborators = collabs
            ..files.addAll(newFiles);
        });
      } else {
        final ownerId = getIt<UserService>().currentUserId;
        setState(() {
          widget.notes.add(
            Note(
              collaborators: collabs,
              createdAt: DateTime.now(),
              id: event.noteId,
              isOwner: true,
              ownerId: ownerId,
              right: 'owner',
              text: event.text,
              updatedAt: DateTime.now(),
              color: event.color,
              dontFold: event.dontFold,
              position: event.fixedPosition,
              todoList: event.todoList,
              files: newFiles,
            ),
          );
        });
      }

      setState(() {
        widget.notes.sort((a, b) {
          final posA = a.position;
          final posB = b.position;
          if (posA != null && posB != null) return posA.compareTo(posB);
          if (posA != null) return -1;
          if (posB != null) return 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
      });
    } else if (event is NoteDeletedEvent) {
      widget.notes.removeWhere((n) => n.id == event.noteId);
    } else if (event is NoteFileDeletedEvent) {
      for (final note in widget.notes) {
        note.files.removeWhere((f) => f.id == event.fileId);
      }
    }

    AppEventBus.instance.emit(AppOfflineDataChangeEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: Builder(
        builder: (context) {
          final allTags = <String>{};
          for (final note in widget.notes) {
            allTags.addAll(_extractTags(note.text));
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
          if (widget.usingCache)
            Tooltip(
              message: 'Showing cached data — could not reach server',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.cloud_off, color: Colors.orange),
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
              if (confirmed == true) {
                AppEventBus.instance.emit(AppLogoutEvent());
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_notes',
        onPressed: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddNoteScreen(offlineMode: widget.usingCache),
            ),
          );
        },
        tooltip: 'Add note',
        child: const Icon(Icons.add),
      ),
      body: Builder(
        builder: (context) {
          final filtered = _selectedTag == null
              ? widget.notes
              : widget.notes
                    .where((n) => _extractTags(n.text).contains(_selectedTag))
                    .toList();

          return RefreshIndicator(
            onRefresh: () async => AppEventBus.instance.emit(AppSyncEvent()),
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Text(
                            _selectedTag != null
                                ? 'No notes tagged #$_selectedTag.'
                                : 'No notes yet.',
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final note = filtered[index];
                      return NoteCard(
                        note: note,
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
