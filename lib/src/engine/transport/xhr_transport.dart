import 'dart:io';
import 'package:socket_io/src/engine/transport/polling_transport.dart';

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
class XHRTransport extends PollingTransport {
  XHRTransport(HttpRequest req): super(req);

  /**
   * Overrides `onRequest` to handle `OPTIONS`..
   *
   * @param {http.IncomingMessage}
   * @api private
   */
  onRequest(HttpRequest req) {
    if ('OPTIONS' == req.method) {
      var res = req.response;
      Map headers = this.headers(req);
      headers['Access-Control-Allow-Headers'] = 'Content-Type';
      headers.forEach((key, value) {
        res.headers.set(key, value);
      });
      res.statusCode = 200;

      res.close();
    } else {
      super.onRequest(req);
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

  if (req.headers.value('origin') != null) {
    headers['Access-Control-Allow-Credentials'] = 'true';
    headers['Access-Control-Allow-Origin'] = req.headers.value('origin');
  } else {
    headers['Access-Control-Allow-Origin'] = '*';
  }
    return super.headers(req, headers);
  }
}