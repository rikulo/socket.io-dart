/// event_emitter.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///     11/23/2016, Created by Henri Chen<henrichen@potix.com>
///
/// Copyright (C) 2016 Potix Corporation. All Rights Reserved.
import 'dart:collection' show HashMap;

/// Handler type for handling the event emitted by an [EventEmitter].
typedef EventHandler<T> = dynamic Function(T data);

/// Generic event emitting and handling.
class EventEmitter {
  /// Mapping of events to a list of event handlers
  Map<String, List<EventHandler>> _events =
      HashMap<String, List<EventHandler>>();

  /// Mapping of events to a list of one-time event handlers
  Map<String, List<EventHandler>> _eventsOnce =
      HashMap<String, List<EventHandler>>();

  /// This function triggers all the handlers currently listening
  /// to [event] and passes them [data].
  void emit(String event, [dynamic data]) {
    final list0 = _events[event];
    // todo: try to optimize this. Maybe remember the off() handlers and remove later?
    // handler might be off() inside handler; make a copy first
    final list = list0 != null ? List.from(list0) : null;
    list?.forEach((handler) {
      handler(data);
    });

    _eventsOnce.remove(event)?.forEach((EventHandler handler) {
      handler(data);
    });
  }

  /// This function binds the [handler] as a listener to the [event]
  void on(String event, EventHandler handler) {
    _events.putIfAbsent(event, () => <EventHandler>[]);
    _events[event]!.add(handler);
  }

  /// This function binds the [handler] as a listener to the first
  /// occurrence of the [event]. When [handler] is called once,
  /// it is removed.
  void once(String event, EventHandler handler) {
    _eventsOnce.putIfAbsent(event, () => <EventHandler>[]);
    _eventsOnce[event]!.add(handler);
  }

  /// This function attempts to unbind the [handler] from the [event]
  void off(String event, [EventHandler? handler]) {
    if (handler != null) {
      _events[event]?.remove(handler);
      _eventsOnce[event]?.remove(handler);
      if (_events[event]?.isEmpty == true) {
        _events.remove(event);
      }
      if (_eventsOnce[event]?.isEmpty == true) {
        _eventsOnce.remove(event);
      }
    } else {
      _events.remove(event);
      _eventsOnce.remove(event);
    }
  }

  /// This function unbinds all the handlers for all the events.
  void clearListeners() {
    _events = HashMap<String, List<EventHandler>>();
    _eventsOnce = HashMap<String, List<EventHandler>>();
  }

  /// Returns whether the event has registered.
  bool hasListeners(String event) {
    return _events[event]?.isNotEmpty == true ||
        _eventsOnce[event]?.isNotEmpty == true;
  }
}
