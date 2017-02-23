/**
 * websocket_transport.dart
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
import 'package:socket_io/src/engine/parser/packet.dart';
import 'package:socket_io/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/transports.dart';

class WebSocketTransport extends Transport {
  static Logger _logger = new Logger('socket_io:transport/WebSocketTransport');
  String name = 'websocket';
  bool writable;
  HttpRequest req;
  WebSocket socket;
  bool get handlesUpgrades => true;
  bool get supportsFraming => true;

  WebSocketTransport(this.req, this.socket) {
    socket.listen(this.onData, onError: this.onError, onDone: this.onClose);
    writable = true;
  }

  void send(List<Packet> packets) {
    var send = (String data, Packet packet) {
      _logger.info('writing "$data"');

      // always creates a new object since ws modifies it
//      var opts = {};
//      if (packet.options != null) {
//        opts['compress'] = packet.options['compress'];
//      }
//
//      if (this.perMessageDeflate != null) {
//        var len = data is String ? UTF8.encode(data).length : data.length;
//        if (len < this.perMessageDeflate['threshold']) {
//          opts['compress'] = false;
//        }
//      }

//      this.writable = false;
      this.socket.add(data);
    };

//    function onEnd (err) {
//      if (err) return self.onError('write error', err.stack);
//      self.writable = true;
//      self.emit('drain');
//    }
    for (var i = 0; i < packets.length; i++) {
      var packet = packets[i];
      if (packet is Map)
        packet = new Packet.fromJSON(packet);
      PacketParser.encodePacket(packet, supportsBinary: this.supportsBinary, callback: (_) => send(_, packet));
    }
  }
  void doClose([fn]) {
    this.socket.close();
    if (fn != null)
      fn();
  }
}