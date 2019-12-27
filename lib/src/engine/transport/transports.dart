/// transports.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///    17/02/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
import 'package:logging/logging.dart';
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io_common/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/jsonp_transport.dart';
import 'package:socket_io/src/engine/transport/websocket_transport.dart';
import 'package:socket_io/src/engine/transport/xhr_transport.dart';
import 'package:socket_io/src/util/event_emitter.dart';

class Transports {
  static List<String> upgradesTo(String from) {
    if ('polling' == from) {
      return ['websocket'];
    }
    return [];
  }

  static Transport newInstance(String name, SocketConnect connect) {
    if ('websocket' == name) {
      return WebSocketTransport(connect);
    } else if ('polling' == name) {
      if (connect.request.uri.queryParameters.containsKey('j')) {
        return JSONPTransport(connect);
      } else {
        return XHRTransport(connect);
      }
    } else {
      throw UnsupportedError('Unknown transport $name');
    }
  }
}

abstract class Transport extends EventEmitter {
  static final Logger _logger = Logger('socket_io:transport.Transport');
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
    readyState = 'open';
    discarded = false;
    var options = connect.dataset['options'];
    if (options != null) {
      messageHandler = options.containsKey('messageHandlerFactory')
          ? options['messageHandlerFactory'](this, connect)
          : null;
    }
  }

  void discard() {
    discarded = true;
  }

  void onRequest(SocketConnect connect) {
    this.connect = connect;
  }

  void close([dynamic Function() closeFn]) {
    if ('closed' == readyState || 'closing' == readyState) return;
    readyState = 'closing';
    doClose(closeFn);
  }

  void doClose([dynamic Function() callback]);

  void onError(msg, [desc]) {
    writable = false;
    if (hasListeners('error')) {
      emit('error', {'msg': msg, 'desc': desc, 'type': 'TransportError'});
    } else {
      _logger.fine('ignored transport error $msg ($desc)');
    }
  }

  void onPacket(Map packet) {
    emit('packet', packet);
  }

  void onData(data) {
    if (messageHandler != null) {
      messageHandler.handle(this, data);
    } else {
      onPacket(PacketParser.decodePacket(data));
    }
  }

  void onClose() {
    readyState = 'closed';
    emit('close');
  }

  void send(List<Map> data);

  bool get supportsFraming;
  bool get handlesUpgrades;
}

abstract class MessageHandler {
  void handle(Transport transport, /*String|List<int>*/ message);
}
