/**
 * connect.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *    06/03/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */
import 'package:stream/stream.dart';
import 'dart:async';
import 'dart:io';

class SocketConnect extends HttpConnectWrapper {
  WebSocket _socket;
  Completer _done;
  bool _completed;
  SocketConnect(HttpConnect origin) : super(origin);

  SocketConnect.fromWebSocket(HttpConnect origin, WebSocket socket)
      : super(origin) {
    _socket = socket;
  }

  bool isUpgradeRequest() => _socket != null;

  WebSocket get websocket => _socket;

  Future get done {
    if (_completed == true) {
      return Future.value('done');
    }
    if (_socket != null)
      return _socket.done;
    else {
      _done = Completer();
      return _done.future;
    }
  }

  /// Closes the current connection.
  void close() {
    if (_done != null) {
      _done.complete('done');
    } else if (_socket != null) {
      _socket.close();
    } else {
      _completed = true;
    }
  }
}
