import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
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

  Future<bool> _ensureStoragePermission() async {
    // On Android 11+ (API 30+), WRITE_EXTERNAL_STORAGE is revoked for the
    // public Downloads folder; MANAGE_EXTERNAL_STORAGE is required instead.
    // permission_handler returns PermissionStatus.granted on platforms/API levels
    // where a given permission doesn't apply, so requesting
    // manageExternalStorage is safe on all versions.
    final statuses = await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();

    final granted = statuses.values.any((s) => s.isGranted);
    if (granted) return true;

    final permanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    if (permanentlyDenied && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Storage permission required'),
          content: const Text(
            'Please grant storage access in Settings to download files.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                openAppSettings();
                Navigator.of(ctx).pop();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
    return false;
  }

  Future<void> _download() async {
    if (!await _ensureStoragePermission()) return;

    setState(() => _downloading = true);
    int? notifId;
    try {
      notifId = await DownloadNotifications.showProgress(widget.file.fileName);
      final path = '/storage/emulated/0/Download/${widget.file.fileName}';
      await widget.client.downloadFileTo(widget.file.id, path);
      // Notify MediaStore so the file appears in file explorers immediately.
      await const MethodChannel('sophie/media_scanner')
          .invokeMethod('scanFile', {'path': path});
      await DownloadNotifications.showComplete(notifId, widget.file.fileName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: ${widget.file.fileName}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Download error: $e\n$st');
      if (notifId != null) await DownloadNotifications.cancel(notifId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          duration: const Duration(seconds: 8),
        ),
      );
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              widget.file.fileName,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
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
