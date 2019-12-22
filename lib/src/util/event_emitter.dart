/**
 * event_emitter.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *     11/23/2016, Created by Henri Chen<henrichen@potix.com>
 *
 * Copyright (C) 2016 Potix Corporation. All Rights Reserved.
 */
import 'dart:collection' show HashMap;

/**
 * Handler type for handling the event emitted by an [EventEmitter].
 */
typedef dynamic EventHandler<T>(T data);

/**
 * Generic event emitting and handling.
 */
class EventEmitter {
  /**
   * Mapping of events to a list of event handlers
   */
  Map<String, List<EventHandler>> _events;

  /**
   * Mapping of events to a list of one-time event handlers
   */
  Map<String, List<EventHandler>> _eventsOnce;

  /**
   * Constructor
   */
  EventEmitter() {
    this._events = HashMap<String, List<EventHandler>>();
    this._eventsOnce = HashMap<String, List<EventHandler>>();
  }

  /**
   * This function triggers all the handlers currently listening
   * to [event] and passes them [data].
   */
  void emit(String event, [dynamic data]) {
    final list0 = this._events[event];
    // todo: try to optimize this. Maybe remember the off() handlers and remove later?
    // handler might be off() inside handler; make a copy first
    final list = list0 != null ? List.from(list0) : null;
    list?.forEach((handler) {
      handler(data);
    });

    this._eventsOnce.remove(event)?.forEach((EventHandler handler) {
      handler(data);
    });
  }

  /**
   * This function binds the [handler] as a listener to the [event]
   */
  void on(String event, EventHandler handler) {
    this._events.putIfAbsent(event, () => List<EventHandler>());
    this._events[event].add(handler);
  }

  /**
   * This function binds the [handler] as a listener to the first
   * occurrence of the [event]. When [handler] is called once,
   * it is removed.
   */
  void once(String event, EventHandler handler) {
    this._eventsOnce.putIfAbsent(event, () => List<EventHandler>());
    this._eventsOnce[event].add(handler);
  }

  /**
   * This function attempts to unbind the [handler] from the [event]
   */
  void off(String event, [EventHandler handler]) {
    if (handler != null) {
      this._events[event]?.remove(handler);
      this._eventsOnce[event]?.remove(handler);
      if (this._events[event]?.isEmpty == true) {
        this._events.remove(event);
      }
      if (this._eventsOnce[event]?.isEmpty == true) {
        this._eventsOnce.remove(event);
      }
    } else {
      this._events.remove(event);
      this._eventsOnce.remove(event);
    }
  }

  /**
   * This function unbinds all the handlers for all the events.
   */
  void clearListeners() {
    this._events = HashMap<String, List<EventHandler>>();
    this._eventsOnce = HashMap<String, List<EventHandler>>();
  }

  /**
   * Returns whether the event has registered.
   */
  bool hasListeners(String event) {
    return this._events[event]?.isNotEmpty == true ||
        this._eventsOnce[event]?.isNotEmpty == true;
  }
}
