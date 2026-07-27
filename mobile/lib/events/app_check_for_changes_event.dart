import 'package:sophie/models/dashboard_data.dart';
import 'package:sophie/services/app_events.dart';

enum CheckForChangesType { start, result }

class AppCheckForChangesEvent extends AppEvent {
  final CheckForChangesType type;
  final DashboardData? data;

  AppCheckForChangesEvent.start()
    : type = CheckForChangesType.start,
      data = null;
  AppCheckForChangesEvent.result(this.data) : type = CheckForChangesType.result;
}
