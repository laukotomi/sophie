import 'dart:convert';
import 'dart:typed_data';

import 'package:alarm/alarm.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sophie/dialogs/ringtone_picker_dialog.dart';
import 'package:sophie/events/app_logout_event.dart';
import 'package:sophie/events/app_sync_event.dart';
import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/models/settings.dart';
import 'package:sophie/models/task.dart';
import 'package:sophie/services/alert_notifications.dart';
import 'package:sophie/services/app_events.dart';
import 'package:sophie/services/storage.dart';
import 'package:sophie/utils/browser_download_stub.dart'
    if (dart.library.html) 'package:sophie/utils/browser_download_web.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.tasks,
    required this.offlineMode,
  });

  final List<Task> tasks;
  final bool offlineMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _alarmVolume;
  late AlarmSound _alarmSound;
  bool _saving = false;
  bool _testingAlarm = false;
  bool _offlineTransferInProgress = false;

  @override
  void initState() {
    super.initState();
    final settings = Storage.getSettings() ?? Settings();
    _alarmVolume = settings.alarmVolume;
    _alarmSound = settings.alarmSound;
  }

  Future _save() async {
    setState(() => _saving = true);

    try {
      await Storage.setSettings(
        Settings(alarmVolume: _alarmVolume, alarmSound: _alarmSound),
      );
      await AlertNotifications.refreshNotifications(widget.tasks);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future _testAlarm() async {
    setState(() => _testingAlarm = true);

    try {
      final alarmSettings = AlarmSettings(
        id: 1,
        dateTime: DateTime.now(),
        assetAudioPath: _alarmSound.path,
        loopAudio: true,
        vibrate: false,
        androidFullScreenIntent: false,
        volumeSettings: VolumeSettings.fade(
          volume: _alarmVolume,
          fadeDuration: Duration(seconds: 5),
          volumeEnforced: false,
        ),
        notificationSettings: NotificationSettings(
          title: 'Sophie',
          body: 'This is a test alarm.',
          stopButton: 'Stop the alarm',
          icon: 'notification_icon',
          iconColor: Color(0xff862778),
        ),
      );

      await Alarm.set(alarmSettings: alarmSettings);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Test alarm scheduled.')));
    } finally {
      if (mounted) {
        setState(() => _testingAlarm = false);
      }
    }
  }

  Future<void> _showRingtonePicker() async {
    final result = await showRingtonePickerDialog(
      context,
      initialAlarmSound: _alarmSound,
    );

    if (!mounted || result == null) return;

    setState(() {
      _alarmSound = result;
    });
  }

  Future<void> _logOut() async {
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
  }

  Future<void> _exportDashboardData() async {
    if (_offlineTransferInProgress) return;

    final data = Storage.getDashboardData();
    if (data == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No data found to export.')));
      return;
    }

    setState(() => _offlineTransferInProgress = true);
    try {
      final payload = jsonEncode(data.toJson());
      final bytes = Uint8List.fromList(utf8.encode(payload));
      final filename =
          'sophie-data-${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Export Sophie data',
        fileName: filename,
        bytes: bytes,
      );

      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported Sophie data to $savedPath')),
        );
      } else {
        // Some platforms may not support direct save dialogs with bytes.
        // Fallback to browser-style download prompt if available.
        saveBytesToBrowserDownload(
          bytes: bytes,
          filename: filename,
          mimeType: 'application/json',
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export started.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _offlineTransferInProgress = false);
      }
    }
  }

  Future<void> _importDashboardData() async {
    if (_offlineTransferInProgress) return;

    setState(() => _offlineTransferInProgress = true);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (!mounted || picked == null || picked.files.isEmpty) {
        return;
      }

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('Selected file bytes are unavailable.');
      }

      final decoded = utf8.decode(bytes);
      final parsed = jsonDecode(decoded) as Map<String, dynamic>;
      final dashboardData = DashboardData.fromJson(parsed);

      await Storage.saveDashboardData(dashboardData);
      await AppEventBus.instance.emit(AppSyncEvent());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported Sophie data from ${file.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _offlineTransferInProgress = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Alarm settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton(
                onPressed: _testingAlarm ? null : _testAlarm,
                child: Text(_testingAlarm ? 'Testing...' : 'Test alarm'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ringtone'),
            subtitle: Text(_alarmSound.title),
            leading: const Icon(Icons.music_note),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showRingtonePicker,
          ),
          const SizedBox(height: 12),
          Text('Volume', style: Theme.of(context).textTheme.titleMedium),
          Text('${(_alarmVolume * 100).round()}%'),
          Slider(
            value: _alarmVolume,
            min: 0,
            max: 1,
            divisions: 20,
            label: '${(_alarmVolume * 100).round()}%',
            onChanged: (value) => setState(() => _alarmVolume = value),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
          const SizedBox(height: 24),
          if (widget.offlineMode) ...[
            Text(
              'Offline mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _offlineTransferInProgress
                            ? null
                            : _exportDashboardData,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Export'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _offlineTransferInProgress
                            ? null
                            : _importDashboardData,
                        icon: const Icon(Icons.download),
                        label: const Text('Import'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              subtitle: const Text('Sign out of this device.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _logOut,
            ),
          ),
        ],
      ),
    );
  }
}
