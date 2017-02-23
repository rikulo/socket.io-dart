/**
 * adapter.dart
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
import 'dart:async';
import 'package:socket_io/src/namespace.dart';
import 'package:socket_io/src/parser/parser.dart';
import 'package:socket_io/src/util/event_emitter.dart';

abstract class Adapter {
  Map nsps = {};
  Map rooms = {};
  Map sids = {};

  add(String id, String room, [fn([_])]);
  del(String id, String room, [fn([_])]);
  delAll(String id, [fn([_])]);
  broadcast(Map packet, [Map opts]);
  clients(List rooms, [fn([_])]);
  clientRooms(String id, [fn(err, [_])]);

  static Adapter newInstance(String key, Namespace nsp) {
    if ('default' == key ) {
      return new _MemoryStoreAdapter(nsp);
    }
    throw new UnimplementedError('not supported other adapter yet.');
  }
}
class _MemoryStoreAdapter extends EventEmitter implements Adapter {
  Map nsps = {};
  Map<String, _Room> rooms;
  Map<String, Map> sids;
  Encoder encoder;
  Namespace nsp;
  _MemoryStoreAdapter(nsp) {
    this.nsp = nsp;
    this.rooms = {};
    this.sids = {};
    this.encoder = nsp.server.encoder;
  }

  /**
   * Adds a socket to a room.
   *
   * @param {String} socket id
   * @param {String} room name
   * @param {Function} callback
   * @api public
   */

  add(String id, String room, [fn([_])]) {
    this.sids[id] = this.sids[id] ?? {};
    this.sids[id][room] = true;
    this.rooms[room] = this.rooms[room] ?? new  _Room();
    this.rooms[room].add(id);
    if (fn != null) Timer.run(() => fn(null));
  }

  /**
   * Removes a socket from a room.
   *
   * @param {String} socket id
   * @param {String} room name
   * @param {Function} callback
   * @api public
   */
  del(String id, String room, [fn([_])]) {
    this.sids[id] = this.sids[id] ?? {};
    this.sids[id].remove(room);
    if (this.rooms.containsKey(room)) {
      this.rooms[room].del(id);
      if (this.rooms[room].length == 0)
        this.rooms.remove(room);
    }

    if (fn != null) Timer.run(() => fn(null));
  }

  /**
   * Removes a socket from all rooms it's joined.
   *
   * @param {String} socket id
   * @param {Function} callback
   * @api public
   */
  delAll(String id, [fn([_])]) {
    var rooms = this.sids[id];
    if (rooms != null) {
      for (var room in rooms) {
        if (this.rooms.containsKey(room)) {
          this.rooms[room].del(id);
          if (this.rooms[room].length == 0)
              this.rooms.remove(room);
        }
      }
    }
    this.sids.remove(id);

     if (fn != null) Timer.run(() => fn(null));
  }

  /**
   * Broadcasts a packet.
   *
   * Options:
   *  - `flags` {Object} flags for this packet
   *  - `except` {Array} sids that should be excluded
   *  - `rooms` {Array} list of rooms to broadcast to
   *
   * @param {Object} packet object
   * @api public
   */
  broadcast(Map packet, [Map opts]) {
    opts = opts ?? {};
    List rooms = opts['rooms'] ?? [];
    List except = opts['except'] ?? [];
    Map flags = opts['flags'] ?? {};
    var packetOpts = {
      'preEncoded': true,
      'volatile': flags['volatile'],
      'compress': flags['compress']
    };
    var ids = {};
    var socket;

    packet['nsp'] = this.nsp.name;
    this.encoder.encode(packet, (encodedPackets) {
      if (rooms.isNotEmpty) {
        for (var i = 0; i < rooms.length; i++) {
          var room = this.rooms[rooms[i]];
          if (room == null) continue;
          var sockets = room.sockets;
          for (var id in sockets) {
            if (sockets.containsKey(id)) {
              if (ids[id] != null || except.indexOf(id) >= 0) continue;
              socket = this.nsp.connected[id];
              if (socket != null) {
                socket.packet(encodedPackets, packetOpts);
                ids[id] = true;
              }
            }
          }
        }
      } else {
        for (var id in this.sids.keys) {
            if (except.indexOf(id) >= 0) continue;
            socket = this.nsp.connected[id];
            if (socket != null) socket.packet(encodedPackets, packetOpts);
        }
      }
    });
  }

  /**
   * Gets a list of clients by sid.
   *
   * @param {Array} explicit set of rooms to check.
   * @param {Function} callback
   * @api public
   */
  clients(List rooms, [fn([_])]) {
    rooms = rooms ?? [];

    var ids = {};
    var sids = [];
    var socket;

    if (rooms.isNotEmpty) {
      for (var i = 0; i < rooms.length; i++) {
        var room = this.rooms[rooms[i]];
        if (room == null) continue;
        var sockets = room.sockets;
        for (var id in sockets) {
          if (sockets.containsKey(id)) {
            if (ids[id] != null) continue;
            socket = this.nsp.connected[id];
            if (socket != null) {
              sids.add(id);
              ids[id] = true;
            }
          }
        }
      }
    } else {
      for (var id in this.sids.keys) {
          socket = this.nsp.connected[id];
          if (socket != null) sids.add(id);
      }
    }

    if (fn != null) Timer.run(() => fn(null));
  }

  /**
   * Gets the list of rooms a given client has joined.
   *
   * @param {String} socket id
   * @param {Function} callback
   * @api public
   */
  clientRooms(String id, [fn(err, [_])]) {
    var rooms = this.sids[id];
    if (fn != null) Timer.run(() => fn(null, rooms ? rooms.keys : null));
  }
}
  /**
   * Room constructor.
   *
   * @api private
   */

class _Room {
  Map<String, bool> sockets;
  int length;
  _Room() {
    this.sockets = {};
    this.length = 0;
  }

  /**
   * Adds a socket to a room.
   *
   * @param {String} socket id
   * @api private
   */
  add(String id) {
    if (!this.sockets.containsKey(id)) {
      this.sockets[id] = true;
      this.length++;
    }
  }

  /**
   * Removes a socket from a room.
   *
   * @param {String} socket id
   * @api private
   */
  del(String id) {
    if (this.sockets.containsKey(id)) {
      this.sockets.remove(id);
      this.length--;
    }
  }
}