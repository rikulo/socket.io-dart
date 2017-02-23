/**
 * jsonp_transport.dart
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
import 'dart:convert';
import 'dart:io';
import 'package:socket_io/src/engine/transport/polling_transport.dart';

class JSONPTransport extends PollingTransport {
  String head;
  String foot;
  JSONPTransport(HttpRequest req): super(req) {

    this.head = '___eio[' + (req.uri.queryParameters['j'] ?? '').replaceAll(new RegExp('[^0-9]'), '') + '](';
    this.foot = ');';
  }

  /**
   * Handles incoming data.
   * Due to a bug in \n handling by browsers, we expect a escaped string.
   *
   * @api private
   */
  onData(data) {
    // we leverage the qs module so that we get built-in DoS protection
    // and the fast alternative to decodeURIComponent
    data = parse(data)['d'];
    if (data is String) {
      // client will send already escaped newlines as \\\\n and newlines as \\n
      // \\n must be replaced with \n and \\\\n with \\n
      data = data.replaceAllMapped(new RegExp(r'(\\)?\\n'), (match) {
        // TODO: need to verify the case.
        throw new UnimplementedError('Not implemented yet');
//        print(match);
//        match
//      return slashes ? match : '\n';
      });
      super.onData(data.replaceAll(new RegExp(r'\\\\n'), '\\n'));
    }
  }

  /**
   * Performs the write.
   *
   * @api private
   */
  doWrite(data, options, [callback]) {
    // we must output valid javascript, not valid json
    // see: http://timelessrepo.com/json-isnt-a-javascript-subset
    var js = JSON.encode(data)
        .replaceAll(new RegExp(r'\u2028'), '\\u2028')
        .replaceAll(new RegExp(r'\u2029'), '\\u2029');

    // prepare response
    data = this.head + js + this.foot;

    super.doWrite(data, options, callback);
  }

  static Map parse(String query) {
    var search = new RegExp('([^&=]+)=?([^&]*)');
    var result = new Map();

    // Get rid off the beginning ? in query strings.
    if (query.startsWith('?')) query = query.substring(1);

    // A custom decoder.
    decode(String s) => Uri.decodeComponent(s.replaceAll('+', ' '));

    // Go through all the matches and build the result map.
    for (Match match in search.allMatches(query)) {
      result[decode(match.group(1))] = decode(match.group(2));
    }

    return result;
  }
}