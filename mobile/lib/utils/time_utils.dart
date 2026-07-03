class TimeUtils {
  static String pad(int n) => n.toString().padLeft(2, '0');
  static String durationToTime(Duration d) =>
      '${pad(d.inHours)}:${pad(d.inMinutes.remainder(60))}:00';
}
