class Settings {
  double alarmVolume;
  AlarmSound alarmSound;

  Settings({this.alarmVolume = 0.5, this.alarmSound = AlarmSound.sophie});

  Map<String, dynamic> toJson() => {
    'volume': alarmVolume,
    'alarmSound': alarmSound.toJson(),
  };

  factory Settings.fromJson(Map<String, dynamic> json) {
    final settings = Settings();
    settings.alarmVolume = (json['volume'] as num?)?.toDouble() ?? 0.5;
    settings.alarmSound = json['alarmSound'] != null
        ? AlarmSound.fromJson(json['alarmSound'] as Map<String, dynamic>)
        : AlarmSound.sophie;
    return settings;
  }
}

class AlarmSound {
  static const String sophieSoundTitle = 'Sophie sound';
  static const String systemSoundTitle = 'System sound';

  final String title;
  final String? path;

  const AlarmSound({required this.title, this.path});

  Map<String, dynamic> toJson() => {'path': path, 'title': title};

  factory AlarmSound.fromJson(Map<String, dynamic> json) {
    return AlarmSound(
      path: json['path'] as String?,
      title: json['title'] as String,
    );
  }

  static const AlarmSound sophie = AlarmSound(
    path: 'assets/task_alert.mp3',
    title: sophieSoundTitle,
  );

  static const AlarmSound system = AlarmSound(
    title: systemSoundTitle,
    path: null,
  );
}
