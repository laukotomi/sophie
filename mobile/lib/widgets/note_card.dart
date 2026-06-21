import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:sophie/screens/add_note_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/widgets/file_download_chip.dart';
import 'package:sophie/widgets/note_chip.dart';

class NoteCard extends StatefulWidget {
  final Note note;
  final List<AppUser> users;
  final String currentUserId;
  final BackendClient client;
  final VoidCallback onEdited;
  final ScrollController scrollController;
  final bool isActive;

  const NoteCard({
    super.key,
    required this.note,
    required this.users,
    required this.currentUserId,
    required this.client,
    required this.onEdited,
    required this.scrollController,
    this.isActive = true,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final _cardKey = GlobalKey();
  final _overlayController = OverlayPortalController();
  double _overlayTop = 0;
  double _overlayRight = 0;
  bool _acquiringLock = false;
  bool _collapsed = true;
  bool _overflows = false;

  static const double _maxCollapsedHeight = 300;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(NoteCard old) {
    super.didUpdateWidget(old);
    if (old.scrollController != widget.scrollController) {
      old.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
    if (!widget.isActive && _overlayController.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayController.isShowing) _overlayController.hide();
      });
    }
    if (widget.isActive && !old.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.isActive) {
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
    final shouldFloat = cardTop < viewTop && cardBottom > viewTop + 56 + 75;

    // debugPrint(
    //   '[NoteCard] cardTop=$cardTop cardBottom=$cardBottom '
    //   'viewTop=$viewTop buttonBottom=${cardTop + 56} '
    //   'shouldFloat=$shouldFloat isShowing=${_overlayController.isShowing}',
    // );

    if (shouldFloat && !_overlayController.isShowing) {
      _overlayTop = viewTop + 4;
      _overlayRight =
          MediaQuery.sizeOf(context).width - (topLeft.dx + size.width) + 20;
      _overlayController.show();
    } else if (!shouldFloat && _overlayController.isShowing) {
      _overlayController.hide();
    }
  }

  Future<void> _openEdit(BuildContext ctx) async {
    if (_acquiringLock) return;
    setState(() => _acquiringLock = true);

    String latestText;
    try {
      latestText = await widget.client.acquireNoteLock(widget.note.id);
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
      if (!ctx.mounted) return;
      setState(() => _acquiringLock = false);
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Failed to open note for editing.')),
      );
      return;
    }

    if (!ctx.mounted) return;
    widget.note.text = latestText;
    setState(() => _acquiringLock = false);

    final edited = await Navigator.of(ctx).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddNoteScreen(
          client: widget.client,
          users: widget.users,
          currentUserId: widget.currentUserId,
          existingNote: widget.note,
        ),
      ),
    );
    if (edited == true) widget.onEdited();
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
                      .map(
                        (f) => FileDownloadChip(file: f, client: widget.client),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoteBody() {
    final content = SelectionArea(
      child: MarkdownBody(
        data: _preserveBlankLines(widget.note.text),
        softLineBreak: true,
        onTapLink: (_, href, _) {
          if (href != null) {
            launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
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
        _CollapsibleBody(
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
}

/// Clips [child] to [maxHeight] when [collapsed], and calls [onOverflowDetected]
/// post-frame whenever the child's natural height exceeds [maxHeight].
class _CollapsibleBody extends SingleChildRenderObjectWidget {
  const _CollapsibleBody({
    required this.maxHeight,
    required this.collapsed,
    required this.onOverflowDetected,
    required Widget child,
  }) : super(child: child);

  final double maxHeight;
  final bool collapsed;
  final void Function(bool overflows) onOverflowDetected;

  @override
  _RenderCollapsibleBody createRenderObject(BuildContext context) =>
      _RenderCollapsibleBody(
        maxHeight: maxHeight,
        collapsed: collapsed,
        onOverflowDetected: onOverflowDetected,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCollapsibleBody renderObject,
  ) {
    renderObject
      ..maxHeight = maxHeight
      ..collapsed = collapsed
      ..onOverflowDetected = onOverflowDetected;
  }
}

class _RenderCollapsibleBody extends RenderProxyBox {
  _RenderCollapsibleBody({
    required double maxHeight,
    required bool collapsed,
    required void Function(bool) onOverflowDetected,
  }) : _maxHeight = maxHeight,
       _collapsed = collapsed,
       _onOverflowDetected = onOverflowDetected;

  double _maxHeight;
  double get maxHeight => _maxHeight;
  set maxHeight(double v) {
    if (_maxHeight == v) return;
    _maxHeight = v;
    markNeedsLayout();
  }

  bool _collapsed;
  bool get collapsed => _collapsed;
  set collapsed(bool v) {
    if (_collapsed == v) return;
    _collapsed = v;
    markNeedsLayout();
  }

  void Function(bool) _onOverflowDetected;
  // ignore: avoid_setters_without_getters
  set onOverflowDetected(void Function(bool) v) => _onOverflowDetected = v;

  @override
  void performLayout() {
    // Layout child unconstrained vertically to measure its natural height.
    child!.layout(
      constraints.copyWith(maxHeight: double.infinity),
      parentUsesSize: true,
    );
    final naturalHeight = child!.size.height;
    final overflows = naturalHeight > _maxHeight;

    // Defer notification to avoid calling setState during layout.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _onOverflowDetected(overflows);
    });

    final displayHeight = _collapsed
        ? naturalHeight.clamp(0.0, _maxHeight)
        : naturalHeight;
    size = constraints.constrain(Size(child!.size.width, displayHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_collapsed && child!.size.height > size.height) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (ctx, off) => super.paint(ctx, off),
      );
    } else {
      super.paint(context, offset);
    }
  }
}
