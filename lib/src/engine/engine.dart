/**
 * engine.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *    16/02/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */
import 'package:socket_io/src/engine/server.dart';
import 'package:socket_io/src/util/event_emitter.dart';

class Engine extends EventEmitter {
  static Engine attach(server, [Map options]) {
    var engine = new Server(options);
    engine.attachTo(server, options);
    return engine;
  }
  dynamic operator [](Object key) {}

  /**
   * Associates the [key] with the given [value].
   *
   * If the key was already in the map, its associated value is changed.
   * Otherwise the key-value pair is added to the map.
   */
  void operator []=(String key, dynamic value) {}
//  init() {}
//  upgrades() {}
//  verify() {}
//  prepare() {}
  close() {}
//  handleRequest() {}
//  handshake() {}
}