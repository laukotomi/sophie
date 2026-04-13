import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shared [FlutterLocalNotificationsPlugin] instance used by all notification
/// services. Calling [initNotificationsPlugin] more than once is a no-op.
final sharedNotificationsPlugin = FlutterLocalNotificationsPlugin();

bool _initialized = false;

/// Initialises the plugin with an Android launcher icon.
/// Safe to call from [main] — no Activity required.
Future<void> initNotificationsPlugin() async {
  if (_initialized) return;
  _initialized = true;
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/launcher_icon'),
  );
  await sharedNotificationsPlugin.initialize(settings: settings);
}
