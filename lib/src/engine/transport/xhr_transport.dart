/**
 * xhr_transport.dart
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
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io/src/engine/transport/polling_transport.dart';

class XHRTransport extends PollingTransport {
  XHRTransport(SocketConnect connect) : super(connect);

  /// Overrides `onRequest` to handle `OPTIONS`..
  ///
  /// @param {http.IncomingMessage}
  /// @api private
  @override
  void onRequest(SocketConnect connect) {
    HttpRequest req = connect.request;
    if ('OPTIONS' == req.method) {
      var res = req.response;
      Map headers = this.headers(connect);
      headers['Access-Control-Allow-Headers'] = 'Content-Type';
      headers.forEach((key, value) {
        res.headers.set(key, value);
      });
      res.statusCode = 200;

      connect.close();
    } else {
      super.onRequest(connect);
    }
  }

  /// Returns headers for a response.
  ///
  /// @param {http.IncomingMessage} request
  /// @param {Object} extra headers
  /// @api private
  @override
  Map headers(SocketConnect connect, [Map headers]) {
    headers = headers ?? {};
    var req = connect.request;
    if (req.headers.value('origin') != null) {
      headers['Access-Control-Allow-Credentials'] = 'true';
      headers['Access-Control-Allow-Origin'] = req.headers.value('origin');
    } else {
      headers['Access-Control-Allow-Origin'] = '*';
    }
    return super.headers(connect, headers);
  }
}
