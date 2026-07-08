class TimeUtils {
  static String pad(int n) => n.toString().padLeft(2, '0');
  static String durationToTime(Duration d) =>
      '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:00';

  static Duration timeToDuration(String timeBeforeStr) {
    final parts = timeBeforeStr.split(':');
    if (parts.length != 3) {
      throw Exception('Invalid time format: $timeBeforeStr');
    }
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return Duration(hours: hours, minutes: minutes);
  }
}
