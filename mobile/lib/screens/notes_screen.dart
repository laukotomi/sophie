import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/events/app_data_change_event.dart';
import 'package:sophie/events/app_offline_mode_changed_event.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/events/note_saved_event.dart';
import 'package:sophie/events/note_sync_event.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/screens/event_manager_screen.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend.dart';
import 'package:sophie/services/note_events.dart';
import 'package:sophie/screens/add_note_screen.dart';
import 'package:sophie/services/base_event.dart';
import 'package:sophie/services/storage.dart';
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
  late final EventSubscription<NoteEvent> _noteEventSub;
  late final AppEventSubscription _appEventSub;

  String? _selectedTag;
  int _pendingSyncs = 0;

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
    _noteEventSub = NoteEventBus.instance.listen(_handleNoteEvent);
    _appEventSub = AppEventBus.instance.listen((event) async {
      if (event is NoteSyncEvent) {
        await _syncNoteChanges();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _noteEventSub.cancel();
    _appEventSub.cancel();
    super.dispose();
  }

  Future _syncNoteChanges() async {
    try {
      final events = await Storage.getOfflineNoteEvents();
      if (events.isEmpty) return;
      final seenSavedNoteIds = <String>{};

      for (final event in events) {
        if (event is NoteSavedEvent) {
          event.skipConflictCheck = !seenSavedNoteIds.add(event.noteId);
        }

        try {
          if (!event.applied) {
            await event.apply(widget.notes, _safeSetState);
          }

          await event.sync(widget.notes, _safeSetState);
          await Storage.removeNoteEvent(event.eventId);
        } on UnauthorizedException {
          await Storage.removeNoteEvent(event.eventId);
        } on NotFoundException {
          await Storage.removeNoteEvent(event.eventId);
        }
      }
    } catch (e) {
      await AppEventBus.instance.emit(
        AppOfflineModeChangedEvent(offlineMode: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing note changes: $e')),
        );
      }

      rethrow;
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future _handleNoteEvent(NoteEvent event) async {
    await event.apply(widget.notes, _safeSetState);
    event.applied = true;

    await AppEventBus.instance.emit(AppDataChangeEvent());

    if (!widget.usingCache) {
      _safeSetState(() => _pendingSyncs++);
      unawaited(_syncEventInBackground(event));
    }
  }

  Future _syncEventInBackground(NoteEvent event) async {
    try {
      await event.sync(widget.notes, _safeSetState);
      event.synced = true;
    } catch (e) {
      await AppEventBus.instance.emit(
        AppOfflineModeChangedEvent(offlineMode: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error syncing note changes: $e')),
        );
      }
    } finally {
      _safeSetState(() => _pendingSyncs--);
    }
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
          if (_pendingSyncs > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (widget.usingCache)
            Tooltip(
              message: 'Showing cached data — could not reach server',
              child: IconButton(
                icon: const Icon(Icons.cloud_off, color: Colors.orange),
                onPressed: () async {
                  final noteEvents = await Storage.getOfflineNoteEvents();
                  if (!context.mounted) return;
                  final events = noteEvents
                      .map<BaseEvent>((event) => event)
                      .toList();
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => EventManagerScreen(
                        events: events,
                        onDeleteEvent: (event) =>
                            Storage.removeNoteEvent(event.eventId),
                      ),
                    ),
                  );
                },
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
                await AppEventBus.instance.emit(AppLogoutEvent());
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
            onRefresh: () async =>
                await AppEventBus.instance.emit(AppSyncEvent()),
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
