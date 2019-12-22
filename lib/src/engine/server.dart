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
import 'dart:convert';
import 'dart:io' hide Socket;
import 'package:logging/logging.dart';
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io/src/engine/engine.dart';
import 'package:socket_io/src/engine/socket.dart';
import 'package:socket_io/src/engine/transport/transports.dart';
import 'package:stream/stream.dart';
import 'package:uuid/uuid.dart';

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
  static final Logger _logger = Logger("socket_io:engine.Server");
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
  Uuid _uuid =  Uuid();

  Server([Map opts]) {
    clients = {};
    clientsCount = 0;

    opts = opts ?? {};

    pingTimeout = opts['pingTimeout'] ?? 60000;
    pingInterval = opts['pingInterval'] ?? 25000;
    upgradeTimeout = opts['upgradeTimeout'] ?? 10000;
    maxHttpBufferSize = opts['maxHttpBufferSize'] ?? 10E7;
    transports = ['polling', 'websocket'];
    allowUpgrades = false != opts['allowUpgrades'];
    allowRequest = opts['allowRequest'];
    cookie = opts['cookie'] == false
        ? false
        : opts['cookie'] ??
            'io'; //false != opts.cookie ? (opts.cookie || 'io') : false;
    cookiePath = opts['cookiePath'] == false
        ? false
        : opts['cookiePath'] ??
            '/'; //false != opts.cookiePath ? (opts.cookiePath || '/') : false;
    cookieHttpOnly = opts['cookieHttpOnly'] != false;

    if (!opts.containsKey('perMessageDeflate') ||
        opts['perMessageDeflate'] == true) {
      perMessageDeflate =
          opts['perMessageDeflate'] is Map ? opts['perMessageDeflate'] : {};
      if (!perMessageDeflate.containsKey('threshold'))
        perMessageDeflate['threshold'] = 1024;
    }
    httpCompression = opts['httpCompression'] ?? {};
    if (!httpCompression.containsKey('threshold'))
      httpCompression['threshold'] = 1024;

    initialPacket = opts['initialPacket'];
    _init();
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
    if (!allowUpgrades) return null;
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
    if (transports.indexOf(transport) == -1) {
      _logger.fine('unknown transport "$transport"');
      return fn(ServerErrors.UNKNOWN_TRANSPORT, false);
    }

    // sid check
    var sid = req.uri.queryParameters['sid'];
    if (sid != null) {
      if (!clients.containsKey(sid)) {
        return fn(ServerErrors.UNKNOWN_SID, false);
      }
      if (!upgrade && clients[sid].transport.name != transport) {
        _logger.fine('bad request: unexpected transport without upgrade');
        return fn(ServerErrors.BAD_REQUEST, false);
      }
    } else {
      // handshake is GET only
      if ('GET' != req.method)
        return fn(ServerErrors.BAD_HANDSHAKE_METHOD, false);
      if (allowRequest == null) return fn(null, true);
      return allowRequest(req, fn);
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
    for (var key in clients.keys) {
      if (clients[key] != null) {
        clients[key].close(true);
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
    verify(connect, false, (err, success) {
      if (!success) {
        sendErrorMessage(req, err);
        return;
      }
//print('sid ${req.uri.queryParameters['sid']}');
      if (req.uri.queryParameters['sid'] != null) {
        _logger.fine('setting new request for existing client');
        self.clients[req.uri.queryParameters['sid']].transport
            .onRequest(connect);
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
      res.statusCode = HttpStatus.forbidden;
      res.headers.contentType = ContentType.json;
      res.write(json.encode({
        'code': ServerErrors.FORBIDDEN,
        'message': code ?? ServerErrorMessages[ServerErrors.FORBIDDEN]
      }));
      return;
    }
    if (req.headers.value('origin') != null) {
      res.headers.add('Access-Control-Allow-Credentials', 'true');
      res.headers
          .add('Access-Control-Allow-Origin', req.headers.value('origin'));
    } else {
      res.headers.add('Access-Control-Allow-Origin', '*');
    }
    res.statusCode = HttpStatus.badRequest;
    res.write(
        json.encode({'code': code, 'message': ServerErrorMessages[code]}));
  }

  /**
   * generate a socket id.
   * Overwrite this method to generate your custom socket id
   *
   * @param {Object} request object
   * @api public
   */
  generateId(SocketConnect connect) {
    return _uuid.v1().replaceAll('-', '');
  }

  /**
   * Handshakes a new client.
   *
   * @param {String} transport name
   * @param {Object} request object
   * @api private
   */
  handshake(String transportName, SocketConnect connect) {
    var id = generateId(connect);

    _logger.fine('handshaking client $id');
    var transport;
    var req = connect.request;
    try {
      transport = Transports.newInstance(transportName, connect);
      if ('polling' == transportName) {
        transport.maxHttpBufferSize = maxHttpBufferSize;
        transport.httpCompression = httpCompression;
      } else if ('websocket' == transportName) {
        transport.perMessageDeflate = perMessageDeflate;
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
    var socket = Socket(id, this, transport, connect);

    if (false != cookie) {
      transport.on('headers', (headers) {
        headers['Set-Cookie'] = '${cookie}=${Uri.encodeComponent(id)}' +
            (cookiePath?.isNotEmpty == true
                ? '; Path=${cookiePath}'
                : '') +
            (cookiePath?.isNotEmpty == true && cookieHttpOnly == true
                ? '; HttpOnly'
                : '');
      });
    }

    transport.onRequest(connect);

    clients[id] = socket;
    clientsCount++;

    socket.once('close', (_) {
      clients.remove(id);
      clientsCount--;
    });

    emit('connection', socket);
  }

  /**
   * Handles an Engine.IO HTTP Upgrade.
   *
   * @api public
   */
  handleUpgrade(SocketConnect connect) {
//  this.prepare(req);

    verify(connect, true, (err, success) {
      if (!success) {
        abortConnection(connect, err);
        return;
      }

//  var head = new Buffer(upgradeHead.length);
//  upgradeHead.copy(head);
//  upgradeHead = null;

      // delegate to ws
//  self.ws.handleUpgrade(req, socket, head, function (conn) {
      onWebSocket(connect);
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
    if (connect.request.connectionInfo == null) {
      _logger.fine('WebSocket connection closed: ${connect.request.uri.path}');
      return;
    }
    // get client id
    var id = connect.request.uri.queryParameters['sid'];

    // keep a reference to the ws.Socket
//  req.websocket = socket;

    if (id != null) {
      var client = clients[id];
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
        transport.perMessageDeflate = perMessageDeflate;
        client.maybeUpgrade(transport);
      }
    } else {
      handshake(connect.request.uri.queryParameters['transport'], connect);
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
    options = options ?? {};
    var path =
        (options['path'] ?? '/engine.io').replaceFirst(RegExp(r"\/$"), '');

    // normalize path
    path += '/';

    // cache and clean up listeners
    server.map('$path.*', (HttpConnect connect) async {
      var req = connect.request;

      _logger.fine('intercepting request for path "$path"');
      if (WebSocketTransformer.isUpgradeRequest(req) &&
          transports.contains('websocket')) {
//          print('init websocket... ${req.uri}');
        var socket = await WebSocketTransformer.upgrade(req);
        var socketConnect = SocketConnect.fromWebSocket(connect, socket);
        socketConnect.dataset['options'] = options;
        handleUpgrade(socketConnect);
        return socketConnect.done;
      } else {
        var socketConnect = SocketConnect(connect);
        socketConnect.dataset['options'] = options;
        handleRequest(socketConnect);
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
    if (socket.readyState == HttpStatus.ok) {
      var message = ServerErrorMessages.containsKey(code)
          ? ServerErrorMessages[code]
          : code;
      var length = utf8.encode(message).length;
      socket.add('HTTP/1.1 400 Bad Request\r\n' +
          'Connection: close\r\n' +
          'Content-type: text/html\r\n' +
          'Content-Length: $length\r\n' +
          '\r\n' +
          message);
    }
    socket.close();
  }
}
