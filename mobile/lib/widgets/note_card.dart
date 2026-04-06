import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:sophie/screens/add_note_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/widgets/file_download_chip.dart';
import 'package:sophie/widgets/note_chip.dart';

class NoteCard extends StatefulWidget {
  final Note note;
  final List<AppUser> users;
  final BackendClient client;
  final VoidCallback onEdited;
  final ScrollController scrollController;

  const NoteCard({
    super.key,
    required this.note,
    required this.users,
    required this.client,
    required this.onEdited,
    required this.scrollController,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final _cardKey = GlobalKey();
  final _overlayController = OverlayPortalController();
  double _overlayTop = 0;
  double _overlayRight = 0;

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
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
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
    final edited = await Navigator.of(ctx).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddNoteScreen(
          client: widget.client,
          users: widget.users,
          existingNote: widget.note,
        ),
      ),
    );
    if (edited == true) widget.onEdited();
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
        child: Material(
          color: Colors.transparent,
          child: IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit note',
            visualDensity: VisualDensity.compact,
            onPressed: () => _openEdit(ctx),
          ),
        ),
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
                  Expanded(
                    child: SelectionArea(
                      child: MarkdownBody(
                        data: _preserveBlankLines(widget.note.text),
                        softLineBreak: true,
                        onTapLink: (_, href, _) {
                          if (href != null) {
                            launchUrl(
                              Uri.parse(href),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit note',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openEdit(context),
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
