import 'package:sophie/utils/time_utils.dart';

class Alert {
  final DateTime? alertAt;
  final Duration? timeBefore;

  const Alert.absolute(DateTime this.alertAt) : timeBefore = null;
  const Alert.relative(Duration this.timeBefore) : alertAt = null;

  Map<String, dynamic> toJson() => {
    'alertAt': alertAt?.toIso8601String(),
    'timeBefore': timeBefore != null
        ? TimeUtils.durationToTime(timeBefore!)
        : null,
  };

  factory Alert.fromJson(Map<String, dynamic> json) {
    final alertAtStr = json['alertAt'] as String?;
    if (alertAtStr != null) {
      return Alert.absolute(DateTime.parse(alertAtStr));
    }

    final timeBeforeStr = json['timeBefore'] as String?;
    if (timeBeforeStr != null) {
      return Alert.relative(TimeUtils.timeToDuration(timeBeforeStr));
    } else {
      throw Exception('Could not parse Alert from JSON: $json');
    }
  }
}
