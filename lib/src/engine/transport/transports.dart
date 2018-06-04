import 'dart:collection';
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
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/jsonp_transport.dart';
import 'package:socket_io/src/engine/transport/websocket_transport.dart';
import 'package:socket_io/src/engine/transport/xhr_transport.dart';
import 'package:socket_io/src/util/event_emitter.dart';
import 'dart:async';

class Transports {
  static List<String> upgradesTo(String from) {
    if ("polling" == from) {
      return ["websocket"];
    }
    return [];
  }

  static Transport newInstance(String name, SocketConnect connect) {
    if ('websocket' == name) {
      return new WebSocketTransport(connect);
    } else if ('polling' == name ) {
      if (connect.request.uri.queryParameters.containsKey('j')) {
        return new JSONPTransport(connect);
      } else {
        return new XHRTransport(connect);
      }
    } else {
      throw new UnsupportedError('Unknown transport $name');
    }
  }
}

abstract class Transport extends EventEmitter {
  static Logger _logger = new Logger('socket_io:transport.Transport');
  double maxHttpBufferSize;
  Map httpCompression;
  Map perMessageDeflate;
  bool supportsBinary;
  String sid;
  String name;
  bool writable;
  String readyState;
  bool discarded;
  SocketConnect connect;
  MessageHandler messageHandler;

  Transport(connect) {
    this.readyState = 'open';
    this.discarded = false;
    var options = connect.dataset['options'];
    if (options != null) {
      messageHandler = options.containsKey('messageHandlerFactory') ? options['messageHandlerFactory'](this, connect) : null;
    }
  }

  void discard() {
    this.discarded = true;
  }

  void onRequest(SocketConnect connect) {
    this.connect = connect;
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
      _logger.fine('ignored transport error $msg ($desc)');
    }
  }

  void onPacket(Map packet) {
    this.emit('packet', packet);
  }

  onData(data) {
    if (messageHandler != null) {
      messageHandler.handle(this, data);
    } else {
      this.onPacket(PacketParser.decodePacket(data));
    }
  }

  void onClose() {
    this.readyState = 'closed';
    this.emit('close');
  }

  void send(List<Map> data);

  bool get supportsFraming;
  bool get handlesUpgrades;

}

abstract class MessageHandler {
  void handle(Transport transport, /*String|List<int>*/ message);
}