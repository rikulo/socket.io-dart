/**
 * namespace.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *    17/02/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */
import 'dart:async';
import 'package:logging/logging.dart';
import 'package:socket_io/src/adapter/adapter.dart';
import 'package:socket_io/src/client.dart';
import 'package:socket_io_common/src/parser/parser.dart';
import 'package:socket_io/src/server.dart';
import 'package:socket_io/src/socket.dart';
import 'package:socket_io/src/util/event_emitter.dart';

/// Blacklisted events.

List<String> events = [
  'connect', // for symmetry with client
  'connection', 'newListener'
];

/// Flags.
List<String> flags = ['json', 'volatile'];

class Namespace extends EventEmitter {
  String name;
  Server server;
  List<Socket> sockets = [];
  Map<String, Socket> connected = {};
  List fns = [];
  int ids = 0;
  List rooms = [];
  Map flags = {};
  Adapter adapter;
  Logger _logger = Logger('socket_io:Namespace');

  /// Namespace constructor.
  ///
  /// @param {Server} server instance
  /// @param {Socket} name
  /// @api private
  Namespace(Server this.server, String this.name) {
    initAdapter();
  }

  /// Initializes the `Adapter` for this nsp.
  /// Run upon changing adapter by `Server#adapter`
  /// in addition to the constructor.
  ///
  /// @api private
  initAdapter() {
    adapter = Adapter.newInstance(server.adapter, this);
  }

  /// Sets up namespace middleware.
  ///
  /// @return {Namespace} self
  /// @api public
  use(fn) {
    fns.add(fn);
    return this;
  }

  /// Executes the middleware for an incoming client.
  ///
  /// @param {Socket} socket that will get added
  /// @param {Function} last fn call in the middleware
  /// @api private
  run(socket, fn) {
    var fns = this.fns.sublist(0);
    if (fns.isEmpty) return fn(null);

    run0(0, fns, socket, fn);
  }

  static run0(idx, fns, socket, fn) {
    return fns[idx](socket, (err) {
      // upon error, short-circuit
      if (err) return fn(err);

      // if no middleware left, summon callback
      if (!fns[idx + 1]) return fn(null);

      // go on to next
      run0(idx + 1, fns, socket, fn);
    });
  }

  /**
   * Targets a room when emitting.
   *
   * @param {String} name
   * @return {Namespace} self
   * @api public
   */
//    in(String name) {
//        to(name);
//    }

  /// Targets a room when emitting.
  ///
  /// @param {String} name
  /// @return {Namespace} self
  /// @api public
  to(String name) {
    rooms = rooms?.isNotEmpty == true ? rooms : [];
    if (!rooms.contains(name)) rooms.add(name);
    return this;
  }

  /// Adds a new client.
  ///
  /// @return {Socket}
  /// @api private
  add(Client client, query, fn) {
    _logger.fine('adding socket to nsp ${name}');
    var socket = Socket(this, client, query);
    var self = this;
    run(socket, (err) {
      // don't use Timer.run() here
      scheduleMicrotask(() {
        if ('open' == client.conn.readyState) {
          if (err != null) return socket.error(err.data || err.message);

          // track socket
          self.sockets.add(socket);

          // it's paramount that the internal `onconnect` logic
          // fires before user-set events to prevent state order
          // violations (such as a disconnection before the connection
          // logic is complete)
          socket.onconnect();
          if (fn != null) fn(socket);

          // fire user-set events
          self.emit('connect', socket);
          self.emit('connection', socket);
        } else {
          _logger.fine('next called after client was closed - ignoring socket');
        }
      });
    });
    return socket;
  }

  /// Removes a client. Called by each `Socket`.
  ///
  /// @api private
  remove(socket) {
    if (sockets.contains(socket)) {
      sockets.remove(socket);
    } else {
      _logger.fine('ignoring remove for ${socket.id}');
    }
  }

  /// Emits to all clients.
  ///
  /// @return {Namespace} self
  /// @api public
  emit(ev, [dynamic arg]) {
    if (events.contains(ev)) {
      super.emit(ev, arg);
    } else {
      // @todo check how to handle it with Dart
      // if (hasBin(args)) { parserType = ParserType.binaryEvent; } // binary

      List data = arg == null ? [ev] : [ev, arg];

      Map packet = {'type': EVENT, 'data': data};

      adapter
          .broadcast(packet, {'rooms': rooms, 'flags': flags});

      rooms = null;
      flags = null;
    }
  }

  /// Sends a `message` event to all clients.
  ///
  /// @return {Namespace} self
  /// @api public
  send([args]) {
    write(args);
  }

  write([args]) {
    emit('message', args);
    return this;
  }

  /// Gets a list of clients.
  ///
  /// @return {Namespace} self
  /// @api public
  clients(fn([_])) {
    adapter.clients(rooms, fn);
    rooms = [];
    return this;
  }

  /// Sets the compress flag.
  ///
  /// @param {Boolean} if `true`, compresses the sending data
  /// @return {Socket} self
  /// @api public
  compress(compress) {
    flags = flags.isEmpty ? flags : {};
    flags['compress'] = compress;
    return this;
  }
}

/**
 * Apply flags from `Socket`.
 */
// @todo
//exports.flags.forEach(function(flag){
//    Namespace.prototype.__defineGetter__(flag, function(){
//    this.flags = this.flags || {};
//    this.flags[flag] = true;
//    return this;
//    });
//});
