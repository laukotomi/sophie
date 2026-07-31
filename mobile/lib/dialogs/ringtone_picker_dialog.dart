import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_system_ringtones/flutter_system_ringtones.dart';
import 'package:sophie/models/settings.dart';
import 'package:sophie/services/ringtone_storage.dart';

Future<AlarmSound?> showRingtonePickerDialog(
  BuildContext context, {
  required AlarmSound initialAlarmSound,
}) {
  return showModalBottomSheet<AlarmSound>(
    context: context,
    showDragHandle: true,
    builder: (_) => RingtonePickerDialog(initialAlarmSound: initialAlarmSound),
  );
}

class RingtonePickerDialog extends StatefulWidget {
  const RingtonePickerDialog({super.key, required this.initialAlarmSound});

  final AlarmSound initialAlarmSound;

  @override
  State<RingtonePickerDialog> createState() => _RingtonePickerDialogState();
}

class _RingtonePickerDialogState extends State<RingtonePickerDialog> {
  bool _loadingRingtones = false;
  String? _previewingTitle;
  late String _selectedTitle;
  List<Ringtone> _alarmSounds = const [];

  @override
  void initState() {
    super.initState();
    _selectedTitle = widget.initialAlarmSound.title;
    _loadRingtones();
  }

  @override
  void dispose() {
    FlutterSystemRingtones.stop();
    super.dispose();
  }

  Future<void> _loadRingtones() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    setState(() => _loadingRingtones = true);

    try {
      final sounds = await FlutterSystemRingtones.getAlarmSounds();
      if (!mounted) return;
      setState(() => _alarmSounds = sounds);
    } finally {
      if (mounted) {
        setState(() => _loadingRingtones = false);
      }
    }
  }

  Future<void> _togglePreview(Ringtone ringtone) async {
    if (_previewingTitle == ringtone.title) {
      await FlutterSystemRingtones.stop();
      if (mounted) {
        setState(() => _previewingTitle = null);
      }
      return;
    }

    await FlutterSystemRingtones.play(ringtone);
    if (mounted) {
      setState(() => _previewingTitle = ringtone.title);
    }
  }

  Future _selectRingtone(Ringtone ringtone) async {
    final path = await RingtoneStorage.prepareAlarmAudioPath(ringtone);

    if (!mounted) return;

    Navigator.of(context).pop(AlarmSound(title: ringtone.title, path: path));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            title: const Text('Sophie sound'),
            subtitle: const Text('Use the built-in Sophie alarm sound.'),
            trailing: _selectedTitle == AlarmSound.sophieSoundTitle
                ? const Icon(Icons.check)
                : null,
            onTap: () => Navigator.of(context).pop(AlarmSound.sophie),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('System default alarm sound'),
            subtitle: const Text('Use the phone default alarm sound.'),
            trailing: _selectedTitle == AlarmSound.systemSoundTitle
                ? const Icon(Icons.check)
                : null,
            onTap: () => Navigator.of(context).pop(AlarmSound.system),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingRingtones
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _alarmSounds.length,
                    itemBuilder: (context, index) {
                      final ringtone = _alarmSounds[index];
                      final selected = _selectedTitle == ringtone.title;
                      final previewing = _previewingTitle == ringtone.title;
                      return ListTile(
                        title: Text(ringtone.title),
                        leading: IconButton(
                          onPressed: () => _togglePreview(ringtone),
                          icon: Icon(
                            previewing ? Icons.stop : Icons.play_arrow,
                          ),
                        ),
                        trailing: selected ? const Icon(Icons.check) : null,
                        onTap: () => _selectRingtone(ringtone),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
