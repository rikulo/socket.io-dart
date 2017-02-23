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
import 'package:socket_io/src/parser/parser.dart';
/**
 * Socket.IO client source.
 */
/**
 * Old settings for backwards compatibility
 */
Map oldSettings = {
  "transports": "transports",
  "heartbeat timeout": "pingTimeout",
  "heartbeat interval": "pingInterval",
  "destroy buffer size": "maxHttpBufferSize"
};

class Server {
  // Namespaces
  Map<String, Namespace> nsps;
  Namespace sockets;
  dynamic _origins;
  bool _serveClient;
  String _path;
  String _adapter;
  HttpServer httpServer;
  Engine engine;
  Encoder encoder;

  Logger _logger = new Logger('socket_io:Server');

  /**
   * Server constructor.
   *
   * @param {http.Server|Number|Object} http server, port or options
   * @param {Object} options
   * @api public
   */
  Server({server: null, Map options}) {
    options = options ?? {};
    this.nsps = {};
    this.path(options.containsKey('path') ? options['path'] : '/socket.io');
    this.serveClient(false != options['serveClient']);
    this.adapter = options.containsKey('adapter') ? options['adapter'] : 'default';
    this.origins(options.containsKey('origins') ? options['origins'] : '*:*');
    this.sockets = this.of('/');
    this.encoder = new Encoder();
    if (server != null) {
      this.attach(server, options);
    }
  }

  /**
   * Server request verification function, that checks for allowed origins
   *
   * @param {http.IncomingMessage} request
   * @param {Function} callback to be called with the result: `fn(err, success)`
   */
  checkRequest(HttpRequest req, [Function fn]) {
    String origin = req.headers.value('origin') != null ? req.headers.value(
        'origin') : req.headers.value('referer');

    // file:// URLs produce a null Origin which can't be authorized via echo-back
    if (origin == null || origin.isEmpty) {
      origin = '*';
    }

    if (!origin.isEmpty && this._origins is Function) {
      return this._origins(origin, fn);
    }

    if (this._origins.contains('*:*')) {
      return fn(null, true);
    }

    if (!origin.isEmpty) {
      try {
        Uri parts = Uri.parse(origin);
        int defaultPort = 'https:' == parts.scheme ? 443 : 80;
        int port = parts.port != null ? parts.port : defaultPort;
        bool ok = this._origins.indexOf(parts.host + ':' + port.toString()) >=
            0 || this._origins.indexOf(parts.host + ':*') >= 0 ||
            this._origins.indexOf('*:' + port.toString()) >= 0;

        return fn(null, ok);
      } catch (ex) {}
    }

    fn(null, false);
  }

  /**
   * Sets/gets whether client code is being served.
   *
   * @param {Boolean} whether to serve client code
   * @return {Server|Boolean} self when setting or value when getting
   * @api public
   */
  serveClient([bool v]) {
    if (v == null) {
      return this._serveClient;
    }

    this._serveClient = v;
    return this;
  }

  /**
   * Backwards compatiblity.
   *
   * @api public
   */
  set(String key, [val]) {
    if ('authorization' == key && val != null) {
      this.use((socket, next) {
        val(socket.request, (err, authorized) {
          if (err) {
            return next(new Exception(err));
          };
          if (!authorized) {
            return next(new Exception('Not authorized'));
          }

          next();
        });
      });
    } else if ('origins' == key && val != null) {
      this.origins(val);
    } else if ('resource' == key) {
      this.path(val);
    } else if (oldSettings[key] && this.engine[oldSettings[key]]) {
      this.engine[oldSettings[key]] = val;
    } else {
      _logger.severe('Option $key is not valid. Please refer to the README.');
    }

    return this;
  }

  /**
   * Sets the client serving path.
   *
   * @param {String} pathname
   * @return {Server|String} self when setting or value when getting
   * @api public
   */
  path([String v]) {
    if (v == null || v.isEmpty) return this._path;
    this._path = v.replaceFirst(new RegExp(r'/\/$/'), '');
    return this;
  }

  /**
   * Sets the adapter for rooms.
   *
   * @param {Adapter} pathname
   * @return {Server|Adapter} self when setting or value when getting
   * @api public
   */
  String get adapter => this._adapter;

  void set adapter(String v) {
    this._adapter = v;
    if (nsps.isNotEmpty) {
      this.nsps.forEach((dynamic i, Namespace nsp) {
        this.nsps[i].initAdapter();
      });
    }
  }

  /**
   * Sets the allowed origins for requests.
   *
   * @param {String} origins
   * @return {Server|Adapter} self when setting or value when getting
   * @api public
   */

  origins([String v]) {
    if (v == null || v.isEmpty) return this._origins;

    this._origins = v;
    return this;
  }

  /**
   * Attaches socket.io to a server or port.
   *
   * @param {http.Server|Number} server or port
   * @param {Object} options passed to engine.io
   * @return {Server} self
   * @api public
   */
  listen(srv, [Map opts]) {
    attach(srv, opts);
  }

  /**
   * Attaches socket.io to a server or port.
   *
   * @param {http.Server|Number} server or port
   * @param {Object} options passed to engine.io
   * @return {Server} self
   * @api public
   */
  attach(srv, [Map opts]) {
    if (srv is Function) {
      String msg = 'You are trying to attach socket.io to an express ' +
          'request handler function. Please pass a http.Server instance.';
      throw new Exception(msg);
    }

    // handle a port as a string
    if (srv is String && int.parse(srv.toString()).toString() == srv) {
      srv = int.parse(srv.toString());
    }
    if (opts == null) {
      opts = new Map();
    }
    // set engine.io path to `/socket.io`
    if (!opts.containsKey('path')) {
      opts['path'] = this.path();
    }
    // set origins verification
    opts['allowRequest'] = this.checkRequest;

    if (srv is num) {
      _logger.info('creating http server and binding to $srv');
      int port = srv;
      HttpServer.bind(InternetAddress.ANY_IP_V4, port).then((
          HttpServer server) {
        this.httpServer = server;
//                server.listen((HttpRequest request) {
//                    HttpResponse response = request.response;
//                    response.statusCode = HttpStatus.NOT_FOUND;
//                    response.close();
//                });

        var connectPacket = { 'type': CONNECT, 'nsp': '/'};
        this.encoder.encode(connectPacket, (encodedPacket) {
          // the CONNECT packet will be merged with Engine.IO handshake,
          // to reduce the number of round trips
          opts['initialPacket'] = encodedPacket;

          _logger.info('creating engine.io instance with opts $opts');
          // initialize engine
          this.engine = Engine.attach(server, opts);

          // attach static file serving
//        if (self._serveClient) self.attachServe(srv);

          // Export http server
          this.httpServer = server;

          // bind to engine events
          this.bind(this.engine);
        });
      });
    } else {
      var connectPacket = { 'type': CONNECT, 'nsp': '/'};
      this.encoder.encode(connectPacket, (encodedPacket) {
        // the CONNECT packet will be merged with Engine.IO handshake,
        // to reduce the number of round trips
        opts['initialPacket'] = encodedPacket;

        _logger.info('creating engine.io instance with opts $opts');
        // initialize engine
        this.engine = Engine.attach(srv, opts);

        // attach static file serving
//        if (self._serveClient) self.attachServe(srv);

        // Export http server
        this.httpServer = srv;

        // bind to engine events
        this.bind(this.engine);
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
//        _logger.info('attaching client serving req handler');
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

  /**
   * Binds socket.io to an engine.io instance.
   *
   * @param {engine.Server} engine.io (or compatible) server
   * @return {Server} self
   * @api public
   */
  bind(engine) {
    this.engine = engine;
    this.engine.on('connection', this.onconnection);
    return this;
  }

  /**
   * Called with each incoming transport connection.
   *
   * @param {engine.Socket} socket
   * @return {Server} self
   * @api public
   */
  onconnection(conn) {
    _logger.info('incoming connection with id ${conn.id}');
    Client client = new Client(this, conn);
    client.connect('/');
    return this;
  }

  /**
   * Looks up a namespace.
   *
   * @param {String} nsp name
   * @param {Function} optional, nsp `connection` ev handler
   * @api public
   */

  of(name, [fn]) {
    if (name.toString()[0] != '/') {
      name = '/' + name;
    }

    if (!this.nsps.containsKey(name)) {
      _logger.info('initializing namespace $name');
      Namespace nsp = new Namespace(this, name);
      this.nsps[name] = nsp;
    }
    if (fn != null) this.nsps[name].on('connect', fn);
    return this.nsps[name];
  }

  /**
   * Closes server connection
   *
   * @api public
   */
  close() {
    this.nsps['/'].sockets.forEach((socket) {
      socket.onclose();
    });

    this.engine.close();

    if (this.httpServer != null) {
      this.httpServer.close();
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

