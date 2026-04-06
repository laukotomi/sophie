import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sophie/backend.dart';
import 'package:sophie/services/download_notifications.dart';

class FileDownloadChip extends StatefulWidget {
  final NoteFile file;
  final BackendClient client;

  const FileDownloadChip({super.key, required this.file, required this.client});

  @override
  State<FileDownloadChip> createState() => _FileDownloadChipState();
}

class _FileDownloadChipState extends State<FileDownloadChip> {
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final notifId = await DownloadNotifications.showProgress(
      widget.file.fileName,
    );
    try {
      final dir = await getExternalStorageDirectory();
      final path = '${dir!.path}/${widget.file.fileName}';
      await widget.client.downloadFileTo(widget.file.id, path);
      await DownloadNotifications.showComplete(notifId, widget.file.fileName);
    } catch (_) {
      await DownloadNotifications.cancel(notifId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to download file')));
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
