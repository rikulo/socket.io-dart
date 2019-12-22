/**
 * server.dart
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
import 'package:logging/logging.dart';
import 'package:socket_io/src/client.dart';
import 'package:socket_io/src/engine/engine.dart';
import 'package:socket_io/src/namespace.dart';
import 'package:socket_io_common/src/parser/parser.dart';
import 'package:stream/stream.dart';

/**
 * Socket.IO client source.
 */
/// Old settings for backwards compatibility
Map oldSettings = {
  'transports': 'transports',
  'heartbeat timeout': 'pingTimeout',
  'heartbeat interval': 'pingInterval',
  'destroy buffer size': 'maxHttpBufferSize'
};

final Logger _logger = Logger('socket_io:Server');

class Server {
  // Namespaces
  Map<String, Namespace> nsps;
  Namespace sockets;
  dynamic _origins;
  bool _serveClient;
  String _path;
  String _adapter;
  StreamServer httpServer;
  Engine engine;
  Encoder encoder;

  /// Server constructor.
  ///
  /// @param {http.Server|Number|Object} http server, port or options
  /// @param {Object} options
  /// @api public
  Server({server: null, Map options}) {
    options = options ?? {};
    nsps = {};
    path(options.containsKey('path') ? options['path'] : '/socket.io');
    serveClient(false != options['serveClient']);
    adapter =
        options.containsKey('adapter') ? options['adapter'] : 'default';
    origins(options.containsKey('origins') ? options['origins'] : '*:*');
    encoder = Encoder();
    sockets = of('/');
    if (server != null) {
      attach(server, options);
    }
  }

  /// Server request verification function, that checks for allowed origins
  ///
  /// @param {http.IncomingMessage} request
  /// @param {Function} callback to be called with the result: `fn(err, success)`
  checkRequest(HttpRequest req, [Function fn]) {
    String origin = req.headers.value('origin') != null
        ? req.headers.value('origin')
        : req.headers.value('referer');

    // file:// URLs produce a null Origin which can't be authorized via echo-back
    if (origin == null || origin.isEmpty) {
      origin = '*';
    }

    if (!origin.isEmpty && _origins is Function) {
      return _origins(origin, fn);
    }

    if (_origins.contains('*:*')) {
      return fn(null, true);
    }

    if (!origin.isEmpty) {
      try {
        Uri parts = Uri.parse(origin);
        int defaultPort = 'https:' == parts.scheme ? 443 : 80;
        int port = parts.port != null ? parts.port : defaultPort;
        bool ok =
            _origins.indexOf(parts.host + ':' + port.toString()) >= 0 ||
                _origins.indexOf(parts.host + ':*') >= 0 ||
                _origins.indexOf('*:' + port.toString()) >= 0;

        return fn(null, ok);
      } catch (ex) {}
    }

    fn(null, false);
  }

  /// Sets/gets whether client code is being served.
  ///
  /// @param {Boolean} whether to serve client code
  /// @return {Server|Boolean} self when setting or value when getting
  /// @api public
  serveClient([bool v]) {
    if (v == null) {
      return _serveClient;
    }

    _serveClient = v;
    return this;
  }

  /// Backwards compatiblity.
  ///
  /// @api public
  set(String key, [val]) {
    if ('authorization' == key && val != null) {
      use((socket, next) {
        val(socket.request, (err, authorized) {
          if (err) {
            return next(Exception(err));
          }
          ;
          if (!authorized) {
            return next(Exception('Not authorized'));
          }

          next();
        });
      });
    } else if ('origins' == key && val != null) {
      origins(val);
    } else if ('resource' == key) {
      path(val);
    } else if (oldSettings[key] && engine[oldSettings[key]]) {
      engine[oldSettings[key]] = val;
    } else {
      _logger.severe('Option $key is not valid. Please refer to the README.');
    }

    return this;
  }

  /// Sets the client serving path.
  ///
  /// @param {String} pathname
  /// @return {Server|String} self when setting or value when getting
  /// @api public
  path([String v]) {
    if (v == null || v.isEmpty) return _path;
    _path = v.replaceFirst(RegExp(r'/\/$/'), '');
    return this;
  }

  /// Sets the adapter for rooms.
  ///
  /// @param {Adapter} pathname
  /// @return {Server|Adapter} self when setting or value when getting
  /// @api public
  String get adapter => _adapter;

  void set adapter(String v) {
    _adapter = v;
    if (nsps.isNotEmpty) {
      nsps.forEach((dynamic i, Namespace nsp) {
        nsps[i].initAdapter();
      });
    }
  }

  /// Sets the allowed origins for requests.
  ///
  /// @param {String} origins
  /// @return {Server|Adapter} self when setting or value when getting
  /// @api public

  origins([String v]) {
    if (v == null || v.isEmpty) return _origins;

    _origins = v;
    return this;
  }

  /// Attaches socket.io to a server or port.
  ///
  /// @param {http.Server|Number} server or port
  /// @param {Object} options passed to engine.io
  /// @return {Server} self
  /// @api public
  listen(srv, [Map opts]) {
    attach(srv, opts);
  }

  /// Attaches socket.io to a server or port.
  ///
  /// @param {http.Server|Number} server or port
  /// @param {Object} options passed to engine.io
  /// @return {Server} self
  /// @api public
  attach(srv, [Map opts]) {
    if (srv is Function) {
      String msg = 'You are trying to attach socket.io to an express ' +
          'request handler function. Please pass a http.Server instance.';
      throw Exception(msg);
    }

    // handle a port as a string
    if (srv is String && int.parse(srv.toString()).toString() == srv) {
      srv = int.parse(srv.toString());
    }
    if (opts == null) {
      opts = {};
    }
    // set engine.io path to `/socket.io`
    if (!opts.containsKey('path')) {
      opts['path'] = path();
    }
    // set origins verification
    opts['allowRequest'] = checkRequest;

    if (srv is num) {
      _logger.fine('creating http server and binding to $srv');
      int port = srv;
      StreamServer server = StreamServer();
      server.start(port: port);
//      HttpServer.bind(InternetAddress.ANY_IP_V4, port).then((
//          HttpServer server) {
//        this.httpServer = server;
////                server.listen((HttpRequest request) {
////                    HttpResponse response = request.response;
////                    response.statusCode = HttpStatus.NOT_FOUND;
////                    response.close();
////                });

      var connectPacket = {'type': CONNECT, 'nsp': '/'};
      encoder.encode(connectPacket, (encodedPacket) {
        // the CONNECT packet will be merged with Engine.IO handshake,
        // to reduce the number of round trips
        opts['initialPacket'] = encodedPacket;

        _logger.fine('creating engine.io instance with opts $opts');
        // initialize engine
        engine = Engine.attach(server, opts);

        // attach static file serving
//        if (self._serveClient) self.attachServe(srv);

        // Export http server
        httpServer = server;

        // bind to engine events
        bind(engine);
      });
//      });
    } else {
      var connectPacket = {'type': CONNECT, 'nsp': '/'};
      encoder.encode(connectPacket, (encodedPacket) {
        // the CONNECT packet will be merged with Engine.IO handshake,
        // to reduce the number of round trips
        opts['initialPacket'] = encodedPacket;

        _logger.fine('creating engine.io instance with opts $opts');
        // initialize engine
        engine = Engine.attach(srv, opts);

        // attach static file serving
//        if (self._serveClient) self.attachServe(srv);

        // Export http server
        httpServer = srv;

        // bind to engine events
        bind(engine);
      });
    }

    return this;
  }

  /**
   * Attaches the static file serving.
   *
   * @param {Function|http.Server} http server
   * @api private
   * @todo Include better way to serve files
   */
//    attachServe(srv){
//        _logger.fine()('attaching client serving req handler');
//        var url = this._path + '/socket.io.js';
//        var evs = srv.listeners('request').slice(0);
//        var self = this;
//        srv.removeAllListeners('request');
//        srv.on('request', function(req, res) {
//        if (0 === req.url.indexOf(url)) {
//        self.serve(req, res);
//        } else {
//        for (var i = 0; i < evs.length; i++) {
//        evs[i].call(srv, req, res);
//        }
//        }
//        })
//    }

  /**
   * Handles a request serving `/socket.io.js`
   *
   * @param {http.Request} req
   * @param {http.Response} res
   * @api private
   * @todo Include better way to serve files
   */

//    serve(req, res){
//        var etag = req.headers['if-none-match'];
//        if (etag) {
//            if (clientVersion == etag) {
//                debug('serve client 304');
//                res.writeHead(304);
//                res.end();
//                return;
//            }
//        }
//
//        debug('serve client source');
//        res.setHeader('Content-Type', 'application/javascript');
//        res.setHeader('ETag', clientVersion);
//        res.writeHead(200);
//        res.end(clientSource);
//    }

  /// Binds socket.io to an engine.io instance.
  ///
  /// @param {engine.Server} engine.io (or compatible) server
  /// @return {Server} self
  /// @api public
  bind(engine) {
    this.engine = engine;
    this.engine.on('connection', onconnection);
    return this;
  }

  /// Called with each incoming transport connection.
  ///
  /// @param {engine.Socket} socket
  /// @return {Server} self
  /// @api public
  onconnection(conn) {
    _logger.fine('incoming connection with id ${conn.id}');
    Client client = Client(this, conn);
    client.connect('/');
    return this;
  }

  /// Looks up a namespace.
  ///
  /// @param {String} nsp name
  /// @param {Function} optional, nsp `connection` ev handler
  /// @api public

  of(name, [fn]) {
    if (name.toString()[0] != '/') {
      name = '/' + name;
    }

    if (!nsps.containsKey(name)) {
      _logger.fine('initializing namespace $name');
      Namespace nsp = Namespace(this, name);
      nsps[name] = nsp;
    }
    if (fn != null) nsps[name].on('connect', fn);
    return nsps[name];
  }

  /// Closes server connection
  ///
  /// @api public
  close() {
    nsps['/'].sockets.forEach((socket) {
      socket.onclose();
    });

    engine.close();

    if (httpServer != null) {
      httpServer.stop();
    }
  }

  // redirect to sockets method
  to(_) => sockets.to(_);
  use(_) => sockets.use(_);
  send(_) => sockets.send(_);
  write(_) => sockets.write(_);
  clients(_) => sockets.clients(_);
  compress(_) => sockets.compress(_);

  // emitter
  emit(event, data) => sockets.emit(event, data);
  on(event, handler) => sockets.on(event, handler);
  once(event, handler) => sockets.once(event, handler);
  off(event, handler) => sockets.off(event, handler);
}
