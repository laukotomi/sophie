import 'package:flutter/material.dart';

abstract class BaseEvent<T> {
  DateTime createdAt = DateTime.now();
  int get eventId => createdAt.millisecondsSinceEpoch;

  String get type;

  bool applied = false;
  bool synced = false;

  Future apply(List<T> items, Function setState);
  Future sync(List<T> items, Function setState);

  @mustCallSuper
  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'type': type,
    'applied': applied,
    'synced': synced,
  };

  static void fromJson(BaseEvent event, Map<String, dynamic> json) {
    if (json.containsKey('createdAt')) {
      event.createdAt = DateTime.parse(json['createdAt'] as String);
    }
    event.applied = json['applied'] as bool? ?? false;
    event.synced = json['synced'] as bool? ?? false;
  }
}

abstract class BaseEventBus<T extends BaseEvent> {
  final handlers = <Future Function(T)>[];

  EventSubscription<T> listen(Future Function(T) handler) {
    handlers.add(handler);
    return EventSubscription._(handlers, handler);
  }

  @mustCallSuper
  Future emit(T event) async {
    await Future.wait(handlers.map((h) => h(event)));
  }
}

class EventSubscription<T extends BaseEvent> {
  final List<Future Function(T)> _handlers;
  final Future Function(T) _handler;

  EventSubscription._(this._handlers, this._handler);

  void cancel() => _handlers.remove(_handler);
}
