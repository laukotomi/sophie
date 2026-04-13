import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sophie/services/notifications_plugin.dart';

class DownloadNotifications {
  static var _nextId = 0;

  static const _channelId = 'downloads';
  static const _channelName = 'Downloads';

  static Future<int> showProgress(String fileName) async {
    final id = _nextId++;
    await sharedNotificationsPlugin.show(
      id: id,
      title: 'Downloading',
      body: fileName,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          showProgress: true,
          indeterminate: true,
          onlyAlertOnce: true,
        ),
      ),
    );
    return id;
  }

  static Future<void> showComplete(int id, String fileName) async {
    await sharedNotificationsPlugin.show(
      id: id,
      title: 'Downloaded',
      body: fileName,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  static Future<void> cancel(int id) =>
      sharedNotificationsPlugin.cancel(id: id);
}

