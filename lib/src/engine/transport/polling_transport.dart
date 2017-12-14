/**
 * polling_transport.dart
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
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/transports.dart';

class PollingTransport extends Transport {
  @override
  bool get handlesUpgrades => false;

  @override
  bool get supportsFraming => false;

  static final Logger _logger = new Logger('socket_io:transport.PollingTransport');
  int closeTimeout;
  Function shouldClose;
  SocketConnect dataReq;
  PollingTransport(connect) : super(connect) {
    this.closeTimeout = 30 * 1000;
    this.maxHttpBufferSize = null;
    this.httpCompression = null;
    this.name = 'polling';
  }

  onRequest(SocketConnect connect) {
    var res = connect.response;

    if ('GET' == connect.request.method) {
      this.onPollRequest(connect);
    } else if ('POST' == connect.request.method) {
      this.onDataRequest(connect);
    } else {
      res.statusCode = 500;
      res.close();
    }
  }
  Map<SocketConnect, Function> _reqCleanups = {};
  Map<SocketConnect, Function> _reqCloses = {};

  /**
   * The client sends a request awaiting for us to send data.
   *
   * @api private
   */
  onPollRequest(SocketConnect connect) {
    if (this.connect != null) {
    _logger.fine('request overlap');
      // assert: this.res, '.req and .res should be (un)set together'
      this.onError('overlap from client');
      this.connect.response.statusCode = 500;
      this.connect.close();
      return;
    }

      _logger.fine('setting request');

    this.connect = connect;

    var onClose = () {
      this.onError('poll connection closed prematurely');
    };

    var cleanup = () {
      _reqCloses.remove(connect);
      this.connect = null;
    };

    _reqCleanups[connect] = cleanup;
    _reqCloses[connect] = onClose;


    this.writable = true;
    this.emit('drain');

    // if we're still writable but had a pending close, trigger an empty send
    if (this.writable && this.shouldClose != null) {
    _logger.fine('triggering empty send to append close packet');
      this.send([{ 'type': 'noop' }]);
    }
  }

  /**
   * The client sends a request with data.
   *
   * @api private
   */
  onDataRequest(SocketConnect connect) {
    if (this.dataReq != null) {
      // assert: this.dataRes, '.dataReq and .dataRes should be (un)set together'
      this.onError('data request overlap from client');
      connect.response.statusCode = 500;
      connect.close();
      return;
    }

    var isBinary = 'application/octet-stream' == connect.request.headers.value('content-type');

    this.dataReq = connect;

    dynamic chunks = isBinary ? [0] : '';
    var self = this;
    StreamSubscription subscription;
    var cleanup = () {
      chunks = isBinary ? [0] : '';
      if (subscription != null) {
        subscription.cancel();
      }
      self.dataReq = null;
    };

    var onClose = () {
      cleanup();
      self.onError('data request connection closed prematurely');
    };

    var onData = (List<int> data) {
      var contentLength;
      if (data is String) {
        chunks += data;
        contentLength = UTF8
            .encode(chunks)
            .length;
      } else {
        if (chunks is String) {
          chunks += new String.fromCharCodes(data);
        } else {
          chunks.addAll(new String.fromCharCodes(data).split(',').map((s) => int.parse(s)).toList());
        }
        contentLength = chunks.length;
      }

      if (contentLength > self.maxHttpBufferSize) {
        chunks = '';
        connect.close();
      }
    };

    var onEnd = () {
      self.onData(chunks);

      var headers = {
      'Content-Type': 'text/html',
      'Content-Length': 2
      };

      HttpResponse res = connect.response;

      res.statusCode = 200;

      res.headers.clear();
      // text/html is required instead of text/plain to avoid an
      // unwanted download dialog on certain user-agents (GH-43)
      self.headers(connect, headers).forEach((key, value) {
        res.headers.set(key, value);
      });
      res.write('ok');
      connect.close();
      cleanup();
    };

    subscription = connect.request.listen(
        onData,
        onDone: onEnd);
    if (!isBinary) {
      connect.response.headers.contentType
      = ContentType.TEXT; // for encoding utf-8
    }
  }

  /**
   * Processes the incoming data payload.
   *
   * @param {String} encoded payload
   * @api private
   */
  onData(data) {
    _logger.fine('received "$data"');
    if (messageHandler != null) {
      messageHandler.handle(this, data);
    } else {
      var self = this;
      var callback = (Map packet, [foo, bar]) {
        if ('close' == packet['type']) {
          _logger.fine('got xhr close packet');
          self.onClose();
          return false;
        }

        self.onPacket(packet);
      };

      PacketParser.decodePayload(data, callback: callback);
    }
  }

  /**
   * Overrides onClose.
   *
   * @api private
   */
  onClose() {
    if (this.writable == true) {
      // close pending poll request
      this.send([{ 'type': 'noop' }]);
    }
    super.onClose();
  }

  /**
   * Writes a packet payload.
   *
   * @param {Object} packet
   * @api private
   */
  send(List packets) {
    this.writable = false;

    if (this.shouldClose != null) {
      _logger.fine('appending close packet to payload');
      packets.add({ 'type': 'close' });
      this.shouldClose();
      this.shouldClose = null;
    }

    var self = this;
    PacketParser.encodePayload(
        packets, supportsBinary: this.supportsBinary, callback: (data) {
      var compress = packets.any((Map packet) {
        var opt = packet['options'];
        return opt != null && opt['compress'] == true;
      });
      self.write(data, {'compress': compress});
    });
  }

  /**
   * Writes data as response to poll request.
   *
   * @param {String} data
   * @param {Object} options
   * @api private
   */
  write(data, [options]) {
    _logger.fine('writing "$data"');
    this.doWrite(data, options, () {
      Function fn = _reqCleanups.remove(this.connect);
      if (fn != null)
        fn();
    });
  }

  /**
   * Performs the write.
   *
   * @api private
   */
  doWrite(data, options, [callback]) {
    var self = this;

    // explicit UTF-8 is required for pages not served under utf
    var isString = data is String;
    var contentType = isString
    ? 'text/plain; charset=UTF-8'
        : 'application/octet-stream';

    var headers = {
    'Content-Type': contentType
    };

    var respond = (data) {
      headers[HttpHeaders.CONTENT_LENGTH] = data is String ? UTF8.encode(data).length : data.length;
      HttpResponse res = self.connect.response;
      res.statusCode = 200;

      res.headers.clear(); // remove all default headers.
      this.headers(this.connect, headers).forEach((k, v) {
        res.headers.set(k, v);
      });
      try {
        if (data is String) {
          res
            .write(data);
          connect.close();
        } else {
          if (headers.containsKey(HttpHeaders.CONTENT_ENCODING)) {
            res.add(data);
          } else {
            res.write(new String.fromCharCodes(data));
          }
            connect.close();
        }
      } catch (e) {
        Function fn = _reqCloses.remove(connect);
        if (fn != null)
          fn();
        rethrow;
      }
      callback();
    };

    if (this.httpCompression == null || options['compress'] != true) {
      respond(data);
      return;
    }

    var len = isString ? UTF8.encode(data).length : data.length;
    if (len < this.httpCompression['threshold']) {
      respond(data);
      return;
    }


    var encodings = this.connect.request.headers.value(HttpHeaders.ACCEPT_ENCODING);
    var gzip = encodings.contains('gzip');
    if (!gzip && !encodings.contains('deflate')) {
      respond(data);
      return;
    }
    var encoding = gzip ? 'gzip' : 'deflate';
//    this.compress(data, encoding, (err, data) {
//      if (err != null) {
//        self.req.response..statusCode = 500..close();
//        callback(err);
//        return;
//      }

      headers[HttpHeaders.CONTENT_ENCODING] = encoding;
      respond(gzip ? GZIP.encode(UTF8.encode(data is List ? new String.fromCharCodes(data as List<int>) : data)) : data);
//    });
  }

  /**
   * Closes the transport.
   *
   * @api private
   */
  doClose([fn()]) {
    _logger.fine('closing');

    var self = this;
    Timer closeTimeoutTimer;

    if (this.dataReq != null) {
    _logger.fine('aborting ongoing data request');
      this.dataReq = null;
    }


    var onClose = () {
      if (closeTimeoutTimer != null)
        closeTimeoutTimer.cancel();
      if (fn != null)
        fn();
      self.onClose();
    };
    if (this.writable == true) {
    _logger.fine('transport writable - closing right away');
      this.send([{ 'type': 'close' }]);
      onClose();
    } else if (this.discarded) {
    _logger.fine('transport discarded - closing right away');
      onClose();
    } else {
    _logger.fine('transport not writable - buffering orderly close');
      this.shouldClose = onClose;
      closeTimeoutTimer = new Timer(new Duration(milliseconds: this.closeTimeout), onClose);
    }
  }

  /**
   * Returns headers for a response.
   *
   * @param {http.IncomingMessage} request
   * @param {Object} extra headers
   * @api private
   */
  headers(SocketConnect connect, [Map headers]) {
    headers = headers ?? {};

    // prevent XSS warnings on IE
    // https://github.com/LearnBoost/socket.io/pull/1333
    var ua = connect.request.headers.value('user-agent');
    if (ua != null && (ua.indexOf(';MSIE') >= 0 || ua.indexOf('Trident/') >= 0)) {
      headers['X-XSS-Protection'] = '0';
    }

    this.emit('headers', headers);
    return headers;
  }
}