import 'dart:async';

/// websocket_transport.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///    22/02/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
import 'package:logging/logging.dart';
import 'package:socket_io_common/src/engine/parser/parser.dart';
import 'package:socket_io/src/engine/transport/transports.dart';

class WebSocketTransport extends Transport {
  static final Logger _logger =
      Logger('socket_io:transport.WebSocketTransport');
  @override
  bool get handlesUpgrades => true;
  @override
  bool get supportsFraming => true;
  StreamSubscription? subscription;
  WebSocketTransport(connect) : super(connect) {
    name = 'websocket';
    this.connect = connect;
    subscription =
        connect.websocket.listen(onData, onError: onError, onDone: onClose);
    writable = true;
  }

  @override
  void send(List<Map> packets) {
    var send = (data, Map packet) {
      _logger.fine('writing "$data"');

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
      connect?.websocket?.add(data);
    };

//    function onEnd (err) {
//      if (err) return self.onError('write error', err.stack);
//      self.writable = true;
//      self.emit('drain');
//    }
    for (var i = 0; i < packets.length; i++) {
      var packet = packets[i];
      PacketParser.encodePacket(packet,
          supportsBinary: supportsBinary, callback: (_) => send(_, packet));
    }
  }

  @override
  void onClose() {
    super.onClose();

    // workaround for https://github.com/dart-lang/sdk/issues/27414
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  @override
  void doClose([fn]) {
    connect?.websocket?.close();
    if (fn != null) fn();
  }
}
