/// polling_transport.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///    22/02/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io_common/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/transports.dart';

class PollingTransport extends Transport {
  @override
  bool get handlesUpgrades => false;

  @override
  bool get supportsFraming => false;

  static final Logger _logger = Logger('socket_io:transport.PollingTransport');
  int closeTimeout;
  Function shouldClose;
  SocketConnect dataReq;
  PollingTransport(connect) : super(connect) {
    closeTimeout = 30 * 1000;
    maxHttpBufferSize = null;
    httpCompression = null;
    name = 'polling';
  }

  @override
  void onRequest(SocketConnect connect) {
    var res = connect.response;

    if ('GET' == connect.request.method) {
      onPollRequest(connect);
    } else if ('POST' == connect.request.method) {
      onDataRequest(connect);
    } else {
      res.statusCode = 500;
      res.close();
    }
  }

  final Map<SocketConnect, Function> _reqCleanups = {};
  final Map<SocketConnect, Function> _reqCloses = {};

  /// The client sends a request awaiting for us to send data.
  ///
  /// @api private
  void onPollRequest(SocketConnect connect) {
    if (this.connect != null) {
      _logger.fine('request overlap');
      // assert: this.res, '.req and .res should be (un)set together'
      onError('overlap from client');
      this.connect.response.statusCode = 500;
      this.connect.close();
      return;
    }

    _logger.fine('setting request');

    this.connect = connect;

    var onClose = () {
      onError('poll connection closed prematurely');
    };

    var cleanup = () {
      _reqCloses.remove(connect);
      this.connect = null;
    };

    _reqCleanups[connect] = cleanup;
    _reqCloses[connect] = onClose;

    writable = true;
    emit('drain');

    // if we're still writable but had a pending close, trigger an empty send
    if (writable && shouldClose != null) {
      _logger.fine('triggering empty send to append close packet');
      send([
        {'type': 'noop'}
      ]);
    }
  }

  /// The client sends a request with data.
  ///
  /// @api private
  void onDataRequest(SocketConnect connect) {
    if (dataReq != null) {
      // assert: this.dataRes, '.dataReq and .dataRes should be (un)set together'
      onError('data request overlap from client');
      connect.response.statusCode = 500;
      connect.close();
      return;
    }

    var isBinary = 'application/octet-stream' ==
        connect.request.headers.value('content-type');

    dataReq = connect;

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

    var onData = (List<int> data) {
      var contentLength;
      if (data is String) {
        chunks += data;
        contentLength = utf8.encode(chunks).length;
      } else {
        if (chunks is String) {
          chunks += String.fromCharCodes(data);
        } else {
          chunks.addAll(String.fromCharCodes(data)
              .split(',')
              .map((s) => int.parse(s))
              .toList());
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

      var headers = {'Content-Type': 'text/html', 'Content-Length': 2};

      var res = connect.response;

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

    subscription = connect.request.listen(onData, onDone: onEnd);
    if (!isBinary) {
      connect.response.headers.contentType =
          ContentType.text; // for encoding utf-8
    }
  }

  /// Processes the incoming data payload.
  ///
  /// @param {String} encoded payload
  /// @api private
  @override
  void onData(data) {
    _logger.fine('received "$data"');
    if (messageHandler != null) {
      messageHandler.handle(this, data);
    } else {
      var self = this;
      var callback = (packet, [foo, bar]) {
        if ('close' == packet['type']) {
          _logger.fine('got xhr close packet');
          self.onClose();
          return false;
        }

        self.onPacket(packet);
        return true;
      };

      PacketParser.decodePayload(data, callback: callback);
    }
  }

  /// Overrides onClose.
  ///
  /// @api private
  @override
  void onClose() {
    if (writable == true) {
      // close pending poll request
      send([
        {'type': 'noop'}
      ]);
    }
    super.onClose();
  }

  /// Writes a packet payload.
  ///
  /// @param {Object} packet
  /// @api private
  @override
  void send(List packets) {
    writable = false;

    if (shouldClose != null) {
      _logger.fine('appending close packet to payload');
      packets.add({'type': 'close'});
      shouldClose();
      shouldClose = null;
    }

    var self = this;
    PacketParser.encodePayload(packets, supportsBinary: supportsBinary,
        callback: (data) {
      var compress = packets.any((packet) {
        var opt = packet['options'];
        return opt != null && opt['compress'] == true;
      });
      self.write(data, {'compress': compress});
    });
  }

  /// Writes data as response to poll request.
  ///
  /// @param {String} data
  /// @param {Object} options
  /// @api private
  void write(data, [options]) {
    _logger.fine('writing "$data"');
    doWrite(data, options, () {
      var fn = _reqCleanups.remove(connect);
      if (fn != null) fn();
    });
  }

  /// Performs the write.
  ///
  /// @api private
  void doWrite(data, options, [callback]) {
    var self = this;

    // explicit UTF-8 is required for pages not served under utf
    var isString = data is String;
    var contentType =
        isString ? 'text/plain; charset=UTF-8' : 'application/octet-stream';

    final headers = {'Content-Type': contentType};

    var respond = (data) {
      headers[HttpHeaders.contentLengthHeader] =
          data is String ? utf8.encode(data).length : data.length;
      var res = self.connect.response;
      res.statusCode = 200;

      res.headers.clear(); // remove all default headers.
      this.headers(connect, headers).forEach((k, v) {
        res.headers.set(k, v);
      });
      try {
        if (data is String) {
          res.write(data);
          connect.close();
        } else {
          if (headers.containsKey(HttpHeaders.contentEncodingHeader)) {
            res.add(data);
          } else {
            res.write(String.fromCharCodes(data));
          }
          connect.close();
        }
      } catch (e) {
        var fn = _reqCloses.remove(connect);
        if (fn != null) fn();
        rethrow;
      }
      callback();
    };

    if (httpCompression == null || options['compress'] != true) {
      respond(data);
      return;
    }

    var len = isString ? utf8.encode(data).length : data.length;
    if (len < httpCompression['threshold']) {
      respond(data);
      return;
    }

    var encodings =
        connect.request.headers.value(HttpHeaders.acceptEncodingHeader);
    var hasGzip = encodings.contains('gzip');
    if (!hasGzip && !encodings.contains('deflate')) {
      respond(data);
      return;
    }
    var encoding = hasGzip ? 'gzip' : 'deflate';
//    this.compress(data, encoding, (err, data) {
//      if (err != null) {
//        self.req.response..statusCode = 500..close();
//        callback(err);
//        return;
//      }

    headers[HttpHeaders.contentEncodingHeader] = encoding;
    respond(hasGzip
        ? gzip.encode(utf8.encode(
            data is List ? String.fromCharCodes(data as List<int>) : data))
        : data);
//    });
  }

  /// Closes the transport.
  ///
  /// @api private
  @override
  void doClose([dynamic Function() fn]) {
    _logger.fine('closing');

    var self = this;
    Timer closeTimeoutTimer;

    if (dataReq != null) {
      _logger.fine('aborting ongoing data request');
      dataReq = null;
    }

    var onClose = () {
      if (closeTimeoutTimer != null) closeTimeoutTimer.cancel();
      if (fn != null) fn();
      self.onClose();
    };
    if (writable == true) {
      _logger.fine('transport writable - closing right away');
      send([
        {'type': 'close'}
      ]);
      onClose();
    } else if (discarded) {
      _logger.fine('transport discarded - closing right away');
      onClose();
    } else {
      _logger.fine('transport not writable - buffering orderly close');
      shouldClose = onClose;
      closeTimeoutTimer = Timer(Duration(milliseconds: closeTimeout), onClose);
    }
  }

  /// Returns headers for a response.
  ///
  /// @param {http.IncomingMessage} request
  /// @param {Object} extra headers
  /// @api private
  Map headers(SocketConnect connect, [Map headers]) {
    headers = headers ?? {};

    // prevent XSS warnings on IE
    // https://github.com/LearnBoost/socket.io/pull/1333
    var ua = connect.request.headers.value('user-agent');
    if (ua != null && (ua.contains(';MSIE') || ua.contains('Trident/'))) {
      headers['X-XSS-Protection'] = '0';
    }

    emit('headers', headers);
    return headers;
  }
}
