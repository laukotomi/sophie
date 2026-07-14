import 'package:sophie/services/app_events.dart';

class AppOfflineModeChangedEvent extends AppEvent {
  final bool offlineMode;

  AppOfflineModeChangedEvent({required this.offlineMode});
}
