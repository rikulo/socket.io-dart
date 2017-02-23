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
import 'package:socket_io/src/engine/parser/packet.dart';
import 'package:socket_io/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/transports.dart';

class PollingTransport extends Transport {
  @override
  bool get handlesUpgrades => false;

  @override
  bool get supportsFraming => false;

  static final Logger _logger = new Logger('socket_io:engine/transport/PollingTransport');
  int closeTimeout;
  Function shouldClose;
  HttpRequest dataReq;
  PollingTransport(req) : super(req) {
    this.closeTimeout = 30 * 1000;
    this.maxHttpBufferSize = null;
    this.httpCompression = null;
  }

  /**
   * Transport name
   *
   * @api public
   */
  String name = 'polling';

  onRequest(HttpRequest req) {
    var res = req.response;

    if ('GET' == req.method) {
      this.onPollRequest(req, res);
    } else if ('POST' == req.method) {
      this.onDataRequest(req);
    } else {
      res.statusCode = 500;
      res.close();
    }
  }
  Map<HttpRequest, Function> _reqCleanups = {};
  Map<HttpRequest, Function> _reqCloses = {};

  /**
   * The client sends a request awaiting for us to send data.
   *
   * @api private
   */
  onPollRequest(HttpRequest req, HttpResponse res) {
    if (this.req != null) {
    _logger.info('request overlap');
      // assert: this.res, '.req and .res should be (un)set together'
      this.onError('overlap from client');
      res.statusCode = 500;
      res.close();
      return;
    }

      _logger.info('setting request');

    this.req = req;

    var onClose = () {
      this.onError('poll connection closed prematurely');
    };

    var cleanup = () {
      _reqCloses.remove(req);
      this.req = null;
    };

    _reqCleanups[req] = cleanup;
    _reqCloses[req] = onClose;


    this.writable = true;
    this.emit('drain');

    // if we're still writable but had a pending close, trigger an empty send
    if (this.writable && this.shouldClose != null) {
    _logger.info('triggering empty send to append close packet');
      this.send([{ 'type': 'noop' }]);
    }
  }

  /**
   * The client sends a request with data.
   *
   * @api private
   */
  onDataRequest(HttpRequest req) {
    if (this.dataReq != null) {
      // assert: this.dataRes, '.dataReq and .dataRes should be (un)set together'
      this.onError('data request overlap from client');
      req.response..statusCode = 500..close();
      return;
    }

    var isBinary = 'application/octet-stream' == req.headers.value('content-type');

    this.dataReq = req;

    var chunks = isBinary ? [0] : '';
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

    var onData = (data) {
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
          chunks.addAll(data);
        }
        contentLength = chunks.length;
      }

      if (contentLength > self.maxHttpBufferSize) {
        chunks = '';
//      req.connection.destroy();
      }
    };

    var onEnd = () {
      self.onData(chunks);

      var headers = {
      'Content-Type': 'text/html',
      'Content-Length': 2
      };

      HttpResponse res = req.response;

      res.statusCode = 200;

      res.headers.clear();
      // text/html is required instead of text/plain to avoid an
      // unwanted download dialog on certain user-agents (GH-43)
      self.headers(req, headers).forEach((key, value) {
        res.headers.set(key, value);
      });
      res..write('ok')..close();
      cleanup();
    };

    subscription = req.listen(
        onData,
        onDone: onEnd);
    if (!isBinary) {
      req.response.headers.contentType
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
    _logger.info('received "$data"');
    var self = this;
    var callback = (Map packet, [foo, bar]) {
      if ('close' == packet['type']) {
      _logger.info('got xhr close packet');
        self.onClose();
        return false;
      }

      self.onPacket(new Packet.fromJSON(packet));
    };

    PacketParser.decodePayload(data, callback: callback);
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
      _logger.info('appending close packet to payload');
      packets.add({ 'type': 'close' });
      this.shouldClose();
      this.shouldClose = null;
    }

    var self = this;
    PacketParser.encodePayload(
        packets, supportsBinary: this.supportsBinary, callback: (data) {
      var compress = packets.any((packet) {
        if (packet is Map) packet = new Packet.fromJSON(packet);
        return packet.options != null && packet.options['compress'] == true;
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
    _logger.info('writing "%s"', data);
    var self = this;
    this.doWrite(data, options, () {
      Function fn = _reqCleanups.remove(self.req);
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
      headers['Content-Length'] = data is String ? UTF8.encode(data).length : data.length;
      HttpResponse res = self.req.response;
      res.statusCode = 200;

      res.headers.clear(); // remove all default headers.
      this.headers(this.req, headers).forEach((k, v) {
        res.headers.set(k, v);
      });
      try {
        if (data is String) {
          res
            ..write(data)
            ..close();
        } else {
          res
            ..write(new String.fromCharCodes(data))
            ..close();
        }
      } catch (e) {
        Function fn = _reqCloses.remove(req);
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


    var encodings = this.req.headers.value(HttpHeaders.ACCEPT_ENCODING);
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

      headers['Content-Encoding'] = encoding;
      respond(gzip ? GZIP.encode(UTF8.encode(data)) : data);
//    });
  }

  /**
   * Closes the transport.
   *
   * @api private
   */
  doClose([fn()]) {
    _logger.info('closing');

    var self = this;
    Timer closeTimeoutTimer;

    if (this.dataReq != null) {
    _logger.info('aborting ongoing data request');
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
    _logger.info('transport writable - closing right away');
      this.send([{ 'type': 'close' }]);
      onClose();
    } else if (this.discarded) {
    _logger.info('transport discarded - closing right away');
      onClose();
    } else {
    _logger.info('transport not writable - buffering orderly close');
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
  headers(HttpRequest req, [Map headers]) {
    headers = headers ?? {};

    // prevent XSS warnings on IE
    // https://github.com/LearnBoost/socket.io/pull/1333
    var ua = req.headers.value('user-agent');
    if (ua != null && (ua.indexOf(';MSIE') >= 0 || ua.indexOf('Trident/') >= 0)) {
      headers['X-XSS-Protection'] = '0';
    }

    this.emit('headers', headers);
    return headers;
  }
}