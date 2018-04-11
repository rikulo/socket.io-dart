# socket.io-dart

Port of awesome JavaScript Node.js library - [Socket.io v2.0.1](https://github.com/socketio/socket.io) - in Dart

## Usage


    import 'package:socket_io/socket_io.dart';

    main() {
        var io = new Server();
        var nsp = io.of('/some');
        nsp.on('connection', (Socket client) {
          print('connection /some');
          client.on('msg', (data) {
            print('data from /some => $data');
            client.emit('fromServer', "ok 2");
          });
        });
          io.on('connection', (Socket client) {
            print('connection default namespace');
            client.on('msg', (data) {
              print('data from default => $data');
              client.emit('fromServer', "ok");
            });
          });
          io.listen(3000);
    }

    // JS client
    var socket = io('http://localhost:3000');
    socket.on('connect', function(){console.log('connect')});
    socket.on('event', function(data){console.log(data)});
    socket.on('disconnect', function(){console.log('disconnect')});
    socket.on('fromServer', function(e){console.log(e)});

    // Dart client
    import 'package:socket_io_client/socket_io_client.dart' as IO;

    IO.Socket socket = IO.io('http://localhost:3000');
    socket.on('connect', (_) {
      print('connect');
      socket.emit('msg', 'test');
    });
    socket.on('event', (data) => print(data));
    socket.on('disconnect', (_) => print('disconnect'));
    socket.on('fromServer', (_) => print(_));

## Multiplexing support

Same as Socket.IO, this project allows you to create several Namespaces, which will act as separate communication channels but will share the same underlying connection.

## Room support

Within each Namespace, you can define arbitrary channels, called Rooms, that sockets can join and leave. You can then broadcast to any given room, reaching every socket that has joined it.

## Transports support
 Refers to [engine.io](https://github.com/socketio/engine.io)

- `polling`: XHR / JSONP polling transport.
- `websocket`: WebSocket transport.

## Adapters support

*  Default socket.io in-memory adapter class. Refers to [socket.io-adapter](https://github.com/socketio/socket.io-adapter)

## Notes to Contributors

### Fork socket.io-dart

If you'd like to contribute back to the core, you can [fork this repository](https://help.github.com/articles/fork-a-repo) and send us a pull request, when it is ready.

If you are new to Git or GitHub, please read [this guide](https://help.github.com/) first.

## Who Uses

* [Quire](https://quire.io) - a simple, collaborative, multi-level task management tool.
* [KEIKAI](https://keikai.io/) - a web spreadsheet for Big Data.

## Socket.io Dart Client

* [socket.io-client-dart](https://github.com/rikulo/socket.io-client-dart)