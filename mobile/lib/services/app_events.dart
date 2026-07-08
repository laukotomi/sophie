import 'dart:async';

class AppEvent {}

class AppEventBus {
  static final AppEventBus instance = AppEventBus._();
  AppEventBus._();

  final _handlers = <Future Function(AppEvent)>[];

  AppEventSubscription listen(Future Function(AppEvent) handler) {
    _handlers.add(handler);
    return AppEventSubscription._(_handlers, handler);
  }

  Future emit(AppEvent event) async {
    await Future.wait(_handlers.map((h) => h(event)));
  }
}

class AppEventSubscription {
  final List<Future Function(AppEvent)> _handlers;
  final Future Function(AppEvent) _handler;

  AppEventSubscription._(this._handlers, this._handler);

  void cancel() => _handlers.remove(_handler);
}
