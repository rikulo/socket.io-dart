/**
 * socket.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *    22/02/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */
import 'dart:io';
import 'package:socket_io/src/adapter/adapter.dart';
import 'package:socket_io/src/client.dart';
import 'package:socket_io/src/parser/parser.dart';
import 'package:socket_io/src/namespace.dart';
import 'package:socket_io/src/server.dart';
import 'package:socket_io/src/util/event_emitter.dart';
/**
 * Module exports.
 */
//
//module.exports = exports = Socket;

/**
 * Blacklisted events.
 *
 * @api public
 */

List events = ['error', 'connect', 'disconnect', 'newListener', 'removeListener'
];

/**
 * Flags.
 *
 * @api private
 */
List flags = ['json', 'volatile', 'broadcast'];

const List EVENTS = const [
'error',
'connect',
'disconnect',
'disconnecting',
'newListener',
'removeListener'
];
class Socket extends EventEmitter {
  // ignore: undefined_class
  Namespace nsp;
  Client client;
  Server server;
  Adapter adapter;
  String id;
  HttpRequest request;
  var conn;
  Map roomMap = {};
  List roomList = [];
  Map acks = {};
  bool connected = true;
  bool disconnected = false;
  Map handshake;
  Map<String, bool> flags;

  // a data store for each socket.
  Map data = {};

  Socket(this.nsp, this.client) {
    this.server = nsp.server;
    this.adapter = this.nsp.adapter;
    this.id = client.id;
    this.request = client.request;
    this.conn = client.conn;
    this.handshake = this.buildHandshake();
  }

  /**
   * Builds the `handshake` BC object
   *
   * @api private
   */
  buildHandshake() {
    return {
      'headers': this.request.headers,
      'time': new DateTime.now().toString(),
      'address': this.conn.remoteAddress,
      'xdomain': this.request.headers.value('origin') != null,
    // TODO  'secure': ! !this.request.connectionInfo.encrypted,
      'issued': new DateTime.now().millisecondsSinceEpoch,
      'url': this.request.uri.path,
      'query': this.request.uri.queryParameters
    };
  }

  Socket get json {
    this.flags = this.flags ?? {};
    this.flags['json'] = true;
    return this;
  }

  Socket get volatile {
    this.flags = this.flags ?? {};
    this.flags['volatile'] = true;
    return this;
  }

  Socket get broadcast {
    this.flags = this.flags ?? {};
    this.flags['broadcast'] = true;
    return this;
  }

  void emit(String event, [data]) {
    emitWithAck(event, data);
  }

  /**
   * Emits to this client.
   *
   * @return {Socket} self
   * @api public
   */
  void emitWithAck(String event, dynamic data, {Function ack}) {
    if (EVENTS.contains(event)) {
      super.emit(event, data);
    } else {
      var packet = {};
      List sendData = data == null ? [event] : [event, data];

      var flags = this.flags ?? {};

      if (ack != null) {
        if (this.roomList.isNotEmpty || flags['broadcast'] == true) {
          throw new UnsupportedError('Callbacks are not supported when broadcasting');
        }

        this.acks['${this.nsp.ids}'] = ack;
        packet['id'] = '${this.nsp.ids++}';
      }

      packet['type'] = /*hasBin(args) ? parser.BINARY_EVENT :*/ EVENT;
      packet['data'] = sendData;


      if (this.roomList.isNotEmpty || flags['broadcast'] == true) {
        this.adapter.broadcast(
            packet, {'except': [this.id], 'rooms': this.roomList, 'flags': flags});
      } else {
        // dispatch packet
        this.packet(
            packet, {'volatile': flags['volatile'], compress: flags['compress']});
      }

//      // reset flags
      this.roomList = [];
      this.flags = null;
//    }
//    return this;
    }
  }

  /**
   * Targets a room when broadcasting.
   *
   * @param {String} name
   * @return {Socket} self
   * @api public
   */
  to(String name) {
    if (!this.roomList.contains(name)) this.roomList.add(name);
    return this;
  }

  /**
   * Sends a `message` event.
   *
   * @return {Socket} self
   * @api public
   */
  send(_) {
      this.write(_);
  }

  write(List data) {
    this.emit('message', data);
    return this;
  }

  /**
   * Writes a packet.
   *
   * @param {Object} packet object
   * @param {Object} options
   * @api private
   */
  packet(packet, [opts]) {

    // ignore preEncoded = true.
    if (packet is Map) {
      packet['nsp'] = this.nsp.name;
    }
    opts = opts ?? {};
    opts['compress'] = false != opts['compress'];
    this.client.packet(packet, opts);
  }

  /**
   * Joins a room.
   *
   * @param {String} room
   * @param {Function} optional, callback
   * @return {Socket} self
   * @api private
   */
  join(room, [fn]) {
//    debug('joining room %s', room);
    if (this.roomMap.containsKey(room)) {
      if (fn != null) fn(null);
      return this;
    }
    this.adapter.add(this.id, room, ([err]) {
      if (err != null) return fn && fn(err);
//      _logger.info('joined room %s', room);
      this.roomMap[room] = room;
      if (fn != null)
        fn(null);
    });
    return this;
  }

  /**
   * Leaves a room.
   *
   * @param {String} room
   * @param {Function} optional, callback
   * @return {Socket} self
   * @api private
   */
  leave(room, fn) {
//    debug('leave room %s', room);
    this.adapter.del(this.id, room, ([err]) {
      if (err != null) return fn && fn(err);
//      _logger.info('left room %s', room);
      this.roomMap.remove(room);
      fn && fn(null);
    });
    return this;
  }

  /**
   * Leave all rooms.
   *
   * @api private
   */

  leaveAll() {
//    this.adapter.delAll(this.id);
    this.roomMap = {};
  }

  /**
   * Called by `Namespace` upon succesful
   * middleware execution (ie: authorization).
   *
   * @api private
   */

  onconnect() {
//    debug('socket connected - writing packet');
    this.nsp.connected[this.id] = this;
    this.join(this.id);
    this.packet({ 'type': CONNECT});
  }

  /**
   * Called with each packet. Called by `Client`.
   *
   * @param {Object} packet
   * @api private
   */

  onpacket(packet) {
//    debug('got packet %j', packet);
    switch (packet['type']) {
      case EVENT:
        this.onevent(packet);
        break;

      case BINARY_EVENT:
        this.onevent(packet);
        break;

      case ACK:
        this.onack(packet);
        break;

      case BINARY_ACK:
        this.onack(packet);
        break;

      case DISCONNECT:
        this.ondisconnect();
        break;

      case ERROR:
        this.emit('error', packet['data']);
    }
  }

  /**
   * Called upon event packet.
   *
   * @param {Object} packet object
   * @api private
   */
  onevent(packet) {
    List args = packet['data'] ?? [];
//    debug('emitting event %j', args);

    if (null != packet['id']) {
//      debug('attaching ack callback to event');
      args.add(this.ack(packet['id']));
    }

    // dart doesn't support "String... rest" syntax.
    if (args.length > 2) {
      Function.apply(super.emit, [args.first, args.sublist(1)]);
    } else {
      Function.apply(super.emit, args);
    }
  }

  /**
   * Produces an ack callback to emit with an event.
   *
   * @param {Number} packet id
   * @api private
   */
  Function ack(id) {
    var sent = false;
    return (_) {
      // prevent double callbacks
      if (sent) return;
//      var args = Array.prototype.slice.call(arguments);
//      debug('sending ack %j', args);

      var type = /*hasBin(args) ? parser.BINARY_ACK : parser.*/ACK;
      packet({'id': id, 'type': type, 'data': [_]});
      sent = true;
    };
  }

  /**
   * Called upon ack packet.
   *
   * @api private
   */
  onack(packet) {
    Function ack = this.acks.remove(packet['id']);
    if (ack is Function) {
//      debug('calling ack %s with %j', packet.id, packet.data);
      Function.apply(ack, packet['data']);
    } else {
//      debug('bad ack %s', packet.id);
    }
  }

  /**
   * Called upon client disconnect packet.
   *
   * @api private
   */
  ondisconnect() {
//    debug('got disconnect packet');
    this.onclose('client namespace disconnect');
  }

  /**
   * Handles a client error.
   *
   * @api private
   */
  onerror(err) {
    if (this
        .hasListeners('error')) {
      this.emit('error', err);
    } else {
//      console.error('Missing error handler on `socket`.');
//      console.error(err.stack);
    }
  }

  /**
   * Called upon closing. Called by `Client`.
   *
   * @param {String} reason
   * @param {Error} optional error object
   * @api private
   */
  onclose([reason]) {
    if (!this.connected) return this;
//    debug('closing socket - reason %s', reason);
    this.leaveAll();
    this.nsp.remove(this);
    this.client.remove(this);
    this.connected = false;
    this.disconnected = true;
    this.nsp.connected.remove(this.id);
    this.emit('disconnect', reason);
  }

  /**
   * Produces an `error` packet.
   *
   * @param {Object} error object
   * @api private
   */
  error(err) {
    this.packet({ 'type': ERROR, 'data': err});
  }

  /**
   * Disconnects this client.
   *
   * @param {Boolean} if `true`, closes the underlying connection
   * @return {Socket} self
   * @api public
   */

  disconnect([close]) {
    if (!this.connected) return this;
    if (close == true) {
      this.client.disconnect();
    } else {
      this.packet({ 'type': DISCONNECT});
      this.onclose('server namespace disconnect');
    }
    return this;
  }

  /**
   * Sets the compress flag.
   *
   * @param {Boolean} if `true`, compresses the sending data
   * @return {Socket} self
   * @api public
   */
  compress(compress) {
    this.flags = this.flags ?? {};
    this.flags['compress'] = compress;
    return this;
  }
}












