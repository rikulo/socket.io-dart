/**
 * transports.dart
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
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:socket_io/src/engine/parser/packet.dart';
import 'package:socket_io/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/jsonp_transport.dart';
import 'package:socket_io/src/engine/transport/websocket_transport.dart';
import 'package:socket_io/src/engine/transport/xhr_transport.dart';
import 'package:socket_io/src/util/event_emitter.dart';

class Transports {
  static List<String> upgradesTo(String from) {
    if ("polling" == from) {
      return ["websocket"];
    }
    return [];
  }

  static Transport newInstance(String name, HttpRequest req,
                               [WebSocket webSocket]) {
    if ('websocket' == name) {
      return new WebSocketTransport(req, webSocket);
    } else if ('polling' == name ) {
      if (req.uri.queryParameters.containsKey('j')) {
        return new JSONPTransport(req);
      } else {
        return new XHRTransport(req);
      }
    } else {
      throw new UnsupportedError('Unknown transport $name');
    }
  }
}

abstract class Transport extends EventEmitter {
  static Logger _logger = new Logger('socket_io:transport/Transport');
  double maxHttpBufferSize;
  Map httpCompression;
  Map perMessageDeflate;
  bool supportsBinary;
  String sid;
  String name;
  bool writable;
  String readyState;
  bool discarded;
  HttpRequest req;

  Transport([HttpRequest req]) {
    this.readyState = 'open';
    this.discarded = false;
  }

  void discard() {
    this.discarded = true;
  }

  void onRequest(HttpRequest req) {
    this.req = req;
  }

  void close([closeFn()]) {
    if ('closed' == this.readyState || 'closing' == this.readyState) return;
    this.readyState = 'closing';
    this.doClose(closeFn);
  }

  void doClose([callback()]);

  void onError(msg, [desc]) {
    this.writable = false;
    if (this.hasListeners('error')) {
      this.emit('error', {'msg': msg, 'desc': desc, 'type': 'TransportError'});
    } else {
      _logger.info('ignored transport error $msg ($desc)');
    }
  }

  void onPacket(Packet packet) {
    this.emit('packet', packet);
  }

  void onData(data) {
    this.onPacket(new Packet.fromJSON(PacketParser.decodePacket(data)));
  }

  void onClose() {
    this.readyState = 'closed';
    this.emit('close');
  }

  void send(List<Packet> data);

  bool get supportsFraming;
  bool get handlesUpgrades;

}