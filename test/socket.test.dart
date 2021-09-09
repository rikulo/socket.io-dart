/// socket.test.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///    16/02/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
import 'package:test/test.dart';

import 'package:socket_io/socket_io.dart';

void main() {
  group('Socket IO', () {
    test('Start standalone server', () async {
      var io = Server();
      var nsp = io.of('/some');
      nsp.on('connection', (client) {
        print('connection /some');
        client.on('msg', (data) {
          print('data from /some => $data');
          client.emit('fromServer', 'ok 2');
        });
      });
      io.on('connection', (client) {
        print('connection default namespace');
        client.on('msg', (data) {
          print('data from default => $data');
          client.emit('fromServer', 'ok');
        });
      });
      await io.listen(3000);
    });
  });
}
