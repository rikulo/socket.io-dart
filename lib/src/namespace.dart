/// namespace.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///    17/02/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
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
  List<Function> fns = [];
  int ids = 0;
  List rooms = [];
  Map flags = {};
  Adapter adapter;
  final Logger _logger = Logger('socket_io:Namespace');

  /// Namespace constructor.
  ///
  /// @param {Server} server instance
  /// @param {Socket} name
  /// @api private
  Namespace(this.server, this.name) {
    initAdapter();
  }

  /// Initializes the `Adapter` for this nsp.
  /// Run upon changing adapter by `Server#adapter`
  /// in addition to the constructor.
  ///
  /// @api private
  void initAdapter() {
    adapter = Adapter.newInstance(server.adapter, this);
  }

  /// Sets up namespace middleware.
  ///
  /// @return {Namespace} self
  /// @api public
  Namespace use(fn) {
    fns.add(fn);
    return this;
  }

  /// Executes the middleware for an incoming client.
  ///
  /// @param {Socket} socket that will get added
  /// @param {Function} last fn call in the middleware
  /// @api private
  void run(socket, Function fn) {
    var fns = this.fns.sublist(0);
    if (fns.isEmpty) return fn(null);

    run0(0, fns, socket, fn);
  }

  //TODO: Figure out return type for this method
  static Object run0(int index, List<Function> fns, Socket socket, Function fn) {
    return fns[index](socket, (err) {
      // upon error, short-circuit
      if (err) return fn(err);

      // if no middleware left, summon callback
      if (fns.length <= index + 1) return fn(null);

      // go on to next
      return run0(index + 1, fns, socket, fn);
    });
  }

  /// Targets a room when emitting.
  ///
  /// @param {String} name
  /// @return {Namespace} self
  /// @api public
//    in(String name) {
//        to(name);
//    }

  /// Targets a room when emitting.
  ///
  /// @param {String} name
  /// @return {Namespace} self
  /// @api public
  Namespace to(String name) {
    rooms = rooms?.isNotEmpty == true ? rooms : [];
    if (!rooms.contains(name)) rooms.add(name);
    return this;
  }

  /// Adds a new client.
  ///
  /// @return {Socket}
  /// @api private
  Socket add(Client client, query, Function fn) {
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
  void remove(socket) {
    if (sockets.contains(socket)) {
      sockets.remove(socket);
    } else {
      _logger.fine('ignoring remove for ${socket.id}');
    }
  }

  /// Emits to all clients.
  ///
  /// @api public
  @override
  void emit(String event, [dynamic argument]) {
    if (events.contains(event)) {
      super.emit(event, argument);
    } else {
      // @todo check how to handle it with Dart
      // if (hasBin(args)) { parserType = ParserType.binaryEvent; } // binary

      // ignore: omit_local_variable_types
      List data = argument == null ? [event] : [event, argument];

      final packet = {'type': EVENT, 'data': data};

      adapter.broadcast(packet, {'rooms': rooms, 'flags': flags});

      rooms = null;
      flags = null;
    }
  }

  /// Sends a `message` event to all clients.
  ///
  /// @return {Namespace} self
  /// @api public
  Namespace send([args]) {
    return write(args);
  }

  Namespace write([args]) {
    emit('message', args);
    return this;
  }

  /// Gets a list of clients.
  ///
  /// @return {Namespace} self
  /// @api public
  ///
  /// TODO: Fix this description or code. Add type parameters to [fn([_])]
  ///
  // ignore: use_function_type_syntax_for_parameters
  Namespace clients(fn([_])) {
    adapter.clients(rooms, fn);
    rooms = [];
    return this;
  }

  /// Sets the compress flag.
  ///
  /// @param {Boolean} if `true`, compresses the sending data
  /// @return {Namespace} self
  /// @api public
  Namespace compress(compress) {
    flags = flags.isEmpty ? flags : {};
    flags['compress'] = compress;
    return this;
  }
}

/// Apply flags from `Socket`.
// @todo
//exports.flags.forEach(function(flag){
//    Namespace.prototype.__defineGetter__(flag, function(){
//    this.flags = this.flags || {};
//    this.flags[flag] = true;
//    return this;
//    });
//});
