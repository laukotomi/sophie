import 'package:sophie/services/app_events.dart';

enum AppMenuTab { notes, tasks }

class AppMenuChangedEvent extends AppEvent {
  final AppMenuTab tab;

  AppMenuChangedEvent({required this.tab});
}
