import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_system_ringtones/flutter_system_ringtones.dart';
import 'package:path_provider/path_provider.dart';

class RingtoneStorage {
  static const _channel = MethodChannel('sophie/ringtone');

  static Future<String?> prepareAlarmAudioPath(Ringtone? ringtone) async {
    if (ringtone == null || kIsWeb) return null;

    if (Platform.isAndroid) {
      return await _channel.invokeMethod<String>('copyUriToAlarmFile', {
        'uri': ringtone.uri,
        'fileName': _buildBaseName(ringtone),
      });
    }

    // This is not tested..
    if (Platform.isIOS) {
      final uri = Uri.parse(ringtone.uri);
      if (!uri.isScheme('file')) return null;

      final source = File.fromUri(uri);
      final docsDir = await getApplicationDocumentsDirectory();
      final directory = Directory('${docsDir.path}/alarm_ringtones');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final fileName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : '${_buildBaseName(ringtone)}.caf';
      final destination = File('${directory.path}/$fileName');
      await source.copy(destination.path);

      return 'alarm_ringtones/$fileName';
    }

    return null;
  }

  static String _buildBaseName(Ringtone ringtone) {
    final safeId = ringtone.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'alarm_ringtone_$safeId';
  }
}
