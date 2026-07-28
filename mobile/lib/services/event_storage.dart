import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sophie/services/base_event.dart';

class EventStorage<T extends BaseEvent> {
  final SharedPreferences _prefs;
  final String _offlineNoteEventsKey;
  final T Function(Map<String, dynamic>) _fromJson;

  EventStorage(this._prefs, this._offlineNoteEventsKey, this._fromJson);

  List<T> getOfflineEvents() {
    final raw = _prefs.getString(_offlineNoteEventsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(_fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future _saveOfflineEvents(List<T> events) async {
    await _prefs.setString(
      _offlineNoteEventsKey,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  Future addOrUpdateEvent(T event) async {
    final list = getOfflineEvents();
    final index = list.indexWhere((e) => e.eventId == event.eventId);
    if (index != -1) {
      list[index] = event;
    } else {
      list.add(event);
    }
    await _saveOfflineEvents(list);
  }

  Future removeEvent(int eventId) async {
    final list = getOfflineEvents();
    final count = list.length;
    list.removeWhere((e) => e.eventId == eventId);

    if (list.length != count) {
      await _saveOfflineEvents(list);
    }
  }
}
