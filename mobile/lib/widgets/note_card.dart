import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:sophie/events/app_menu_changed_event.dart';
import 'package:sophie/main.dart';
import 'package:sophie/models/note.dart';
import 'package:sophie/screens/add_note_screen.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/backend_note.dart';
import 'package:sophie/widgets/collapsible_body.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sophie/widgets/file_download_chip.dart';
import 'package:sophie/widgets/note_chip.dart';

class NoteCard extends StatefulWidget {
  final Note note;
  final ScrollController scrollController;

  const NoteCard({
    super.key,
    required this.note,
    required this.scrollController,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final _cardKey = GlobalKey();
  final _overlayController = OverlayPortalController();
  late final AppEventSubscription _appEventSub;
  double _overlayTop = 0;
  double _overlayRight = 0;
  bool _acquiringLock = false;
  bool _collapsed = true;
  bool _overflows = false;
  final Set<String> _checkedItems = {};

  static const double _maxCollapsedHeight = 300;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _appEventSub = AppEventBus.instance.listen((event) async {
      if (event is AppMenuChangedEvent && event.tab != AppMenuTab.notes) {
        if (_overlayController.isShowing) _overlayController.hide();
      }
    });
  }

  // @override
  // void didUpdateWidget(NoteCard old) {
  //   super.didUpdateWidget(old);
  //   if (old.scrollController != widget.scrollController) {
  //     old.scrollController.removeListener(_onScroll);
  //     widget.scrollController.addListener(_onScroll);
  //   }
  //   _onScroll();
  // }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _appEventSub.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) {
      if (_overlayController.isShowing) _overlayController.hide();
      return;
    }
    final canEdit = widget.note.isOwner || widget.note.right == 'edit';
    if (!canEdit) return;

    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final size = renderBox.size;
    final topLeft = renderBox.localToGlobal(Offset.zero);
    final cardTop = topLeft.dy;
    final cardBottom = cardTop + size.height;

    final mq = MediaQuery.of(context);
    final viewTop = mq.padding.top + kToolbarHeight;

    // Float when the edit button itself (16px padding + ~40px compact button = 56px
    // from card top) has scrolled behind the AppBar, but the card is still visible.
    final shouldFloat =
        cardTop < viewTop && cardBottom > viewTop + kToolbarHeight + 75;

    debugPrint(
      '[NoteCard] cardTop=$cardTop cardBottom=$cardBottom '
      'viewTop=$viewTop buttonBottom=${cardTop + 56} '
      'shouldFloat=$shouldFloat isShowing=${_overlayController.isShowing}',
    );

    if (shouldFloat && !_overlayController.isShowing) {
      _overlayTop = viewTop + 4;
      _overlayRight =
          MediaQuery.sizeOf(context).width - (topLeft.dx + size.width) + 20;
      _overlayController.show();
    } else if (!shouldFloat && _overlayController.isShowing) {
      _overlayController.hide();
    }
  }

  Future _openEdit(BuildContext ctx) async {
    if (_acquiringLock) return;
    setState(() => _acquiringLock = true);

    String latestText;
    bool offlineMode = false;
    try {
      final result = await getIt<BackendNote>().acquireNoteLock(widget.note.id);
      latestText = result.text;
    } on NoteLockedException {
      if (!ctx.mounted) return;
      setState(() => _acquiringLock = false);
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
            'Someone else is editing this note. Please try again later.',
          ),
        ),
      );

      return;
    } catch (_) {
      // Network error: open in offline mode so the user can still edit.
      offlineMode = true;
      latestText = widget.note.text;
    }

    if (!ctx.mounted) return;
    widget.note.text = widget.note.todoList && _checkedItems.isNotEmpty
        ? _removeCheckedItems(latestText)
        : latestText;

    setState(() => _acquiringLock = false);

    await Navigator.of(ctx).push<Object?>(
      MaterialPageRoute(
        builder: (_) =>
            AddNoteScreen(existingNote: widget.note, offlineMode: offlineMode),
      ),
    );
  }

  Widget _editButton(BuildContext ctx) {
    if (_acquiringLock) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.edit_outlined),
      tooltip: 'Edit note',
      visualDensity: VisualDensity.compact,
      onPressed: () => _openEdit(ctx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updatedAt = _formatDate(widget.note.updatedAt);

    final canEdit = widget.note.isOwner || widget.note.right == 'edit';

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (ctx) => Positioned(
        top: _overlayTop,
        right: _overlayRight,
        child: Material(color: Colors.transparent, child: _editButton(ctx)),
      ),
      child: Card(
        key: _cardKey,
        color: widget.note.color != null
            ? Color(
                int.parse('FF${widget.note.color!.substring(1)}', radix: 16),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildNoteBody()),
                  if (canEdit) _editButton(context),
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
                      if (widget.note.isOwner)
                        NoteChip(
                          icon: Icons.edit,
                          label: 'Owner',
                          color: theme.colorScheme.primaryContainer,
                          textColor: theme.colorScheme.onPrimaryContainer,
                        )
                      else
                        NoteChip(
                          icon: widget.note.right == 'edit'
                              ? Icons.edit
                              : Icons.visibility,
                          label: widget.note.right == 'edit'
                              ? 'Can edit'
                              : 'View only',
                          color: theme.colorScheme.secondaryContainer,
                          textColor: theme.colorScheme.onSecondaryContainer,
                        ),
                      ...widget.note.collaborators.map(
                        (c) => NoteChip(
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
              if (widget.note.files.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: widget.note.files
                      .map((f) => FileDownloadChip(file: f))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  MarkdownStyleSheet get _headingStyleSheet {
    final theme = Theme.of(context);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: theme.textTheme.headlineSmall?.copyWith(fontSize: 26),
      h2: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
      h1Padding: const EdgeInsets.only(top: 0, bottom: 8),
      h2Padding: const EdgeInsets.only(top: 16, bottom: 8),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 8),
      h4Padding: const EdgeInsets.only(top: 8, bottom: 8),
      h5Padding: const EdgeInsets.only(top: 8, bottom: 8),
      h6Padding: const EdgeInsets.only(top: 8, bottom: 8),
    );
  }

  Widget _buildNoteBody() {
    final content = widget.note.todoList
        ? _buildTodoListBody()
        : SelectionArea(
            child: MarkdownBody(
              data: _preserveBlankLines(widget.note.text),
              softLineBreak: true,
              styleSheet: _headingStyleSheet,
              onTapLink: (_, href, _) {
                if (href != null) {
                  launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
            ),
          );

    if (widget.note.dontFold) {
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollapsibleBody(
          maxHeight: _maxCollapsedHeight,
          collapsed: _collapsed,
          onOverflowDetected: (overflows) {
            if (overflows != _overflows && mounted) {
              setState(() => _overflows = overflows);
            }
          },
          child: content,
        ),
        if (_overflows)
          GestureDetector(
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _collapsed ? 'Show more' : 'Show less',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                  Icon(
                    _collapsed
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
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

  /// Returns [text] with any list items whose text appears in [_checkedItems]
  /// removed. Used to strip ticked-off todo items before opening the editor.
  String _removeCheckedItems(String text) {
    final lines = text.split('\n');
    final filtered = lines.where((line) {
      final match = RegExp(r'^-\s+(.+)$').firstMatch(line);
      return match == null || !_checkedItems.contains(match.group(1));
    });
    return filtered.join('\n');
  }

  Widget _buildTodoListBody() {
    final theme = Theme.of(context);
    final segments = _parseTodoList(widget.note.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((segment) {
        if (segment is _ListItemSegment) {
          final checked = _checkedItems.contains(segment.text);
          return InkWell(
            onTap: () => setState(() {
              if (checked) {
                _checkedItems.remove(segment.text);
              } else {
                _checkedItems.add(segment.text);
              }
            }),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: checked
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      segment.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: checked
                            ? theme.colorScheme.onSurfaceVariant.withAlpha(128)
                            : null,
                        decoration: checked ? TextDecoration.lineThrough : null,
                        decorationColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (segment is _SpacerSegment) {
          return const SizedBox(height: 16);
        } else {
          final textSeg = segment as _TextSegment;
          return SelectionArea(
            child: MarkdownBody(
              data: _preserveBlankLines(textSeg.text),
              softLineBreak: true,
              styleSheet: _headingStyleSheet,
              onTapLink: (_, href, _) {
                if (href != null) {
                  launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
            ),
          );
        }
      }).toList(),
    );
  }

  static List<_TodoSegment> _parseTodoList(String text) {
    final lines = text.split('\n');
    final segments = <_TodoSegment>[];
    final buffer = StringBuffer();

    void flushBuffer() {
      if (buffer.isEmpty) return;
      final buffered = buffer.toString().trimRight();
      if (buffered.isNotEmpty) {
        segments.add(_TextSegment(buffered));
      } else {
        final lineCount = buffer.toString().split('\n').length - 1;
        for (var i = 0; i < lineCount; i++) {
          segments.add(_SpacerSegment());
        }
      }
      buffer.clear();
    }

    for (final line in lines) {
      final match = RegExp(r'^-\s+(.+)$').firstMatch(line);
      if (match != null) {
        flushBuffer();
        segments.add(_ListItemSegment(match.group(1)!));
      } else {
        buffer.writeln(line);
      }
    }

    flushBuffer();

    return segments;
  }
}

sealed class _TodoSegment {}

class _TextSegment extends _TodoSegment {
  final String text;
  _TextSegment(this.text);
}

class _ListItemSegment extends _TodoSegment {
  final String text;
  _ListItemSegment(this.text);
}

class _SpacerSegment extends _TodoSegment {}
