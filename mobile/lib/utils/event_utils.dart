import 'package:sophie/services/backend.dart';
import 'package:sophie/services/base_event.dart';
import 'package:sophie/services/event_storage.dart';

class EventUtils {
  static Future syncEvent<T extends BaseEvent>(
    Function sync,
    T event,
    EventStorage<T> eventStorage,
  ) async {
    try {
      await sync(event);
      await eventStorage.removeEvent(event.eventId);
    } on UnauthorizedException {
      await eventStorage.removeEvent(event.eventId);
    } on NotFoundException {
      await eventStorage.removeEvent(event.eventId);
    }
  }
}
