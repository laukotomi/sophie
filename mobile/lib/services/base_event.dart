import 'package:flutter/material.dart';

abstract class BaseEvent<T> {
  bool _applied = false;
  bool _synced = false;

  DateTime createdAt = DateTime.now();
  int get eventId => createdAt.millisecondsSinceEpoch;

  String get type;

  Future<bool> apply(List<T> items, Function setState) async {
    if (_applied) return false;

    await onApply(items, setState);
    _applied = true;
    return true;
  }

  Future<bool> sync(List<T> items, Function setState) async {
    if (_synced) return false;

    await onSync(items, setState);
    _synced = true;
    return true;
  }

  Future onApply(List<T> items, Function setState);
  Future onSync(List<T> items, Function setState);

  @mustCallSuper
  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'type': type,
    'applied': _applied,
    'synced': _synced,
  };

  static void fromJson(BaseEvent event, Map<String, dynamic> json) {
    if (json.containsKey('createdAt')) {
      event.createdAt = DateTime.parse(json['createdAt'] as String);
    }
    event._applied = json['applied'] as bool? ?? false;
    event._synced = json['synced'] as bool? ?? false;
  }
}

abstract class BaseEventBus<T extends BaseEvent> {
  final handlers = <Future Function(T)>[];

  List<T> get unappliedEvents;

  void saveUnappliedEvent(T event);

  EventSubscription<T> listen(Future Function(T) handler) {
    handlers.add(handler);
    _emitUnappliedEvents();
    return EventSubscription._(handlers, handler);
  }

  Future emit(T event) async {
    if (handlers.isEmpty) {
      saveUnappliedEvent(event);
    } else {
      await Future.wait(handlers.map((h) => h(event)));
    }
  }

  Future _emitUnappliedEvents() async {
    for (final event in unappliedEvents) {
      await emit(event);
    }
  }
}

class EventSubscription<T extends BaseEvent> {
  final List<Future Function(T)> _handlers;
  final Future Function(T) _handler;

  EventSubscription._(this._handlers, this._handler);

  void cancel() => _handlers.remove(_handler);
}
