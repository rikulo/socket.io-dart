/**
 * server
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
import 'dart:convert';
import 'dart:io' hide Socket;
import 'package:logging/logging.dart';
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io/src/engine/engine.dart';
import 'package:socket_io/src/engine/socket.dart';
import 'package:socket_io/src/engine/transport/transports.dart';
import 'package:stream/stream.dart';
/**
 * Server constructor.
 *
 * @param {Object} options
 * @api public
 */
class ServerErrors {
  static const int UNKNOWN_TRANSPORT = 0;
  static const int UNKNOWN_SID = 1;
  static const int BAD_HANDSHAKE_METHOD = 2;
  static const int BAD_REQUEST = 3;
  static const int FORBIDDEN = 4;
}

const Map<int, String> ServerErrorMessages = const {
  0: 'Transport unknown',
  1: 'Session ID unknown',
  2: 'Bad handshake method',
  3: 'Bad request',
  4: 'Forbidden'
};

class Server extends Engine {
  static final Logger _logger = new Logger("socket_io:engine.Server");
  Map clients;
  int clientsCount;
  int pingTimeout;
  int pingInterval;
  int upgradeTimeout;
  double maxHttpBufferSize;
  List<String> transports;
  bool allowUpgrades;
  Function allowRequest;
  String cookie;
  String cookiePath;
  bool cookieHttpOnly;
  Map perMessageDeflate;
  Map httpCompression;
  dynamic initialPacket;

  Server([Map opts]) {
    clients = {};
    this.clientsCount = 0;

    opts = opts ?? {};

    this.pingTimeout = opts['pingTimeout'] ?? 60000;
    this.pingInterval = opts['pingInterval'] ?? 25000;
    this.upgradeTimeout = opts['upgradeTimeout'] ?? 10000;
    this.maxHttpBufferSize = opts['maxHttpBufferSize'] ?? 10E7;
    this.transports = ['polling', 'websocket'];
    this.allowUpgrades = false != opts['allowUpgrades'];
    this.allowRequest = opts['allowRequest'];
    this.cookie = opts['cookie'] == false ?  false : opts['cookie'] ?? 'io'; //false != opts.cookie ? (opts.cookie || 'io') : false;
    this.cookiePath = opts['cookiePath'] == false ?  false : opts['cookiePath'] ?? '/'; //false != opts.cookiePath ? (opts.cookiePath || '/') : false;
    this.cookieHttpOnly = opts['cookieHttpOnly'] != false;

    if (!opts.containsKey('perMessageDeflate') || opts['perMessageDeflate'] == true) {
      this.perMessageDeflate = opts['perMessageDeflate'] is Map ? opts['perMessageDeflate'] : {};
      if (!this.perMessageDeflate.containsKey('threshold'))
        this.perMessageDeflate['threshold'] = 1024;
    }
    this.httpCompression = opts['httpCompression'] ?? {};
    if (!this.httpCompression .containsKey('threshold'))
      this.httpCompression['threshold'] = 1024;

    this.initialPacket = opts['initialPacket'];
    this._init();
  }

  /**
   * Initialize websocket server
   *
   * @api private
   */

  _init() {
//  if (this.transports.indexOf('websocket') == -1) return;

//  if (this.ws) this.ws.close();
//
//  var wsModule;
//  try {
//    wsModule = require(this.wsEngine);
//  } catch (ex) {
//    this.wsEngine = 'ws';
//    // keep require('ws') as separate expression for packers (browserify, etc)
//    wsModule = require('ws');
//  }
//  this.ws = new wsModule.Server({
//    noServer: true,
//    clientTracking: false,
//    perMessageDeflate: this.perMessageDeflate,
//    maxPayload: this.maxHttpBufferSize
//  });
  }

  /**
   * Returns a list of available transports for upgrade given a certain transport.
   *
   * @return {Array}
   * @api public
   */

  List<String> upgrades(transport) {
    if (!this.allowUpgrades) return null;
    return Transports.upgradesTo(transport);
  }

  /**
   * Verifies a request.
   *
   * @param {http.IncomingMessage}
   * @return {Boolean} whether the request is valid
   * @api private
   */

  verify(SocketConnect connect, bool upgrade, fn) {
    // transport check
    var req = connect.request;
    var transport = req.uri.queryParameters['transport'];
    if (this.transports.indexOf(transport) == -1) {
      _logger.fine('unknown transport "%s"', transport);
      return fn(ServerErrors.UNKNOWN_TRANSPORT, false);
    }

    // sid check
    var sid = req.uri.queryParameters['sid'];
    if (sid != null) {
      if (!this.clients.containsKey(sid)) {
        return fn(ServerErrors.UNKNOWN_SID, false);
      }
      if (!upgrade && this.clients[sid].transport.name != transport) {
        _logger.fine('bad request: unexpected transport without upgrade');
        return fn(ServerErrors.BAD_REQUEST, false);
      }
    } else {
      // handshake is GET only
      if ('GET' != req.method)
        return fn(ServerErrors.BAD_HANDSHAKE_METHOD, false);
      if (this.allowRequest == null) return fn(null, true);
      return this.allowRequest(req, fn);
    }

    fn(null, true);
  }

  /**
   * Closes all clients.
   *
   * @api public
   */

  close() {
    _logger.fine('closing all open clients');
    for (var key in this.clients.keys) {
      if (this.clients[key] != null) {
        this.clients[key].close(true);
      }
    }
//  if (this.ws) {
//    _logger.fine('closing webSocketServer');
//    this.ws.close();
//    // don't delete this.ws because it can be used again if the http server starts listening again
//  }
  }

  /**
   * Handles an Engine.IO HTTP request.
   *
   * @param {http.IncomingMessage} request
   * @param {http.ServerResponse|http.OutgoingMessage} response
   * @api public
   */

  handleRequest(SocketConnect connect) {
    var req = connect.request;
    _logger.fine('handling ${req.method} http request ${req.uri.path}');
//  this.prepare(req);
//  req.res = res;

    var self = this;
    this.verify(connect, false, (err, success) {
      if (!success) {
        sendErrorMessage(req, err);
        return;
      }
//print('sid ${req.uri.queryParameters['sid']}');
      if (req.uri.queryParameters['sid'] != null) {
        _logger.fine('setting new request for existing client');
        self.clients[req.uri.queryParameters['sid']].transport.onRequest(connect);
      } else {
        self.handshake(req.uri.queryParameters['transport'], connect);
      }
    });
  }

  /**
   * Sends an Engine.IO Error Message
   *
   * @param {http.ServerResponse} response
   * @param {code} error code
   * @api private
   */

  static sendErrorMessage(HttpRequest req, code) {
    var res = req.response;
    var isForbidden = !ServerErrorMessages.containsKey(code);
    if (isForbidden) {
      res.statusCode = HttpStatus.FORBIDDEN;
      res.headers.contentType = ContentType.JSON;
      res.write(JSON.encode({
        'code': ServerErrors.FORBIDDEN,
        'message': code ?? ServerErrorMessages[ServerErrors.FORBIDDEN]
      }));
      return;
    }
    if (req.headers.value('origin') != null) {
      res.headers.add('Access-Control-Allow-Credentials', 'true');
      res.headers.add(
          'Access-Control-Allow-Origin', req.headers.value('origin'));
    } else {
      res.headers.add('Access-Control-Allow-Origin', '*');
    }
    res.statusCode = HttpStatus.BAD_REQUEST;
    res.write(
        JSON.encode({'code': code, 'message': ServerErrorMessages[code]}));
  }

  /**
   * generate a socket id.
   * Overwrite this method to generate your custom socket id
   *
   * @param {Object} request object
   * @api public
   */
  generateId(SocketConnect connect) {
    return connect.request.session.id;
  }

  /**
   * Handshakes a new client.
   *
   * @param {String} transport name
   * @param {Object} request object
   * @api private
   */
  handshake(String transportName, SocketConnect connect) {
    var id = this.generateId(connect);

    _logger.fine('handshaking client $id');
    var transport;
    var req = connect.request;
    try {
       transport = Transports.newInstance(transportName, connect);
      if ('polling' == transportName) {
        transport.maxHttpBufferSize = this.maxHttpBufferSize;
        transport.httpCompression = this.httpCompression;
      } else if ('websocket' == transportName) {
        transport.perMessageDeflate = this.perMessageDeflate;
      }

      if (req.uri.hasQuery && req.uri.queryParameters.containsKey('b64')) {
        transport.supportsBinary = false;
      } else {
        transport.supportsBinary = true;
      }
    } catch (e) {
      sendErrorMessage(req, ServerErrors.BAD_REQUEST);
      return;
    }
    var socket = new Socket(id, this, transport, connect);

    if (false != this.cookie) {
      transport.on('headers', (headers) {
        headers['Set-Cookie'] = '${this.cookie}=${Uri.encodeComponent(id)}' +
            (this.cookiePath?.isNotEmpty == true ? '; Path=${this.cookiePath}'
             : '') +
            (this.cookiePath?.isNotEmpty && this.cookieHttpOnly == true ? '; HttpOnly'
             : '');
      });
    }

    transport.onRequest(connect);

    this.clients[id] = socket;
    this.clientsCount++;

    socket.once('close', (_) {
      this.clients.remove(id);
      this.clientsCount--;
    });

    this.emit('connection', socket);
  }

  /**
   * Handles an Engine.IO HTTP Upgrade.
   *
   * @api public
   */
  handleUpgrade(SocketConnect connect) {
//  this.prepare(req);

    var self = this;
    this.verify(connect, true, (err, success) {
      if (!success) {
        abortConnection(connect, err);
        return;
      }

//  var head = new Buffer(upgradeHead.length);
//  upgradeHead.copy(head);
//  upgradeHead = null;

      // delegate to ws
//  self.ws.handleUpgrade(req, socket, head, function (conn) {
      this.onWebSocket(connect);
//  });
    });
  }

  /**
   * Called upon a ws.io connection.
   *
   * @param {ws.Socket} websocket
   * @api private
   */

  onWebSocket(SocketConnect connect) {
//    socket.listen((_) {},
//        onError: () => _logger.fine('websocket error before upgrade'));

//  if (!transports[req._query.transport].handlesUpgrades) {
//    _logger.fine('transport doesnt handle upgraded requests');
//    socket.close();
//    return;
//  }

    // get client id
    var id = connect.request.uri.queryParameters['sid'];

    // keep a reference to the ws.Socket
//  req.websocket = socket;

    if (id != null) {
      var client = this.clients[id];
      if (client == null) {
        _logger.fine('upgrade attempt for closed client');
        connect.websocket.close();
      } else if (client.upgrading == true) {
        _logger.fine('transport has already been trying to upgrade');
        connect.websocket.close();
      } else if (client.upgraded == true) {
        _logger.fine('transport had already been upgraded');
        connect.websocket.close();
      } else {
        _logger.fine('upgrading existing transport');
        var req = connect.request;
        var transport = Transports.newInstance(
            req.uri.queryParameters['transport'], connect);
        if (req.uri.queryParameters['b64'] == true) {
          transport.supportsBinary = false;
        } else {
          transport.supportsBinary = true;
        }
        transport.perMessageDeflate = this.perMessageDeflate;
        client.maybeUpgrade(transport);
      }
    } else {
      this.handshake(connect.request.uri.queryParameters['transport'], connect);
    }
  }

  /**
   * Captures upgrade requests for a http.Server.
   *
   * @param {http.Server} server
   * @param {Object} options
   * @api public
   */
  attachTo(StreamServer server, Map options) {
    var self = this;
    options = options ?? {};
    var path = (options['path'] ?? '/engine.io').replaceFirst(new RegExp(r"\/$"), '');

    var destroyUpgradeTimeout = options['destroyUpgradeTimeout'] ?? 1000;

    // normalize path
    path += '/';

    // cache and clean up listeners
    server.map('$path.*', (HttpConnect connect) async {
      var req = connect.request;

        _logger.fine('intercepting request for path "$path"');
        if (WebSocketTransformer.isUpgradeRequest(req) &&
            this.transports.contains('websocket')) {
          var socket = await WebSocketTransformer.upgrade(req);
          var socketConnect = new SocketConnect.fromWebSocket(connect, socket);
          this.handleUpgrade(socketConnect);
          return socketConnect.done;
        } else {
          var socketConnect = new SocketConnect(connect);
          this.handleRequest(socketConnect);
          return socketConnect.done;
        }
    }, preceding: true);
  }

  /**
   * Closes the connection
   *
   * @param {net.Socket} socket
   * @param {code} error code
   * @api private
   */

  static abortConnection(SocketConnect connect, code) {
    var socket = connect.websocket;
    if (socket.readyState == HttpStatus.OK) {
      var message = ServerErrorMessages.containsKey(code)
                    ? ServerErrorMessages[code] : code;
      var length = UTF8
          .encode(message)
          .length;
      socket.add('HTTP/1.1 400 Bad Request\r\n' + 'Connection: close\r\n' +
          'Content-type: text/html\r\n' + 'Content-Length: $length\r\n' +
          '\r\n' + message);
    }
    socket.close();
  }
}