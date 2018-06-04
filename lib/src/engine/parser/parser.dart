/**
 * parser.dart
 *
 * Purpose:
 *
 * Description:
 *
 * History:
 *    20/02/2017, Created by jumperchen
 *
 * Copyright (C) 2017 Potix Corporation. All Rights Reserved.
 */
import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:socket_io/src/engine/parser/wtf8.dart';

// Protocol version
final protocol = 3;

enum PacketType {
  OPEN,
  CLOSE,
  PING,
  PONG,
  MESSAGE,
  UPGRADE,
  NOOP
}

const List<String> PacketTypeList = const <String>[
  'open', 'close', 'ping', 'pong', 'message', 'upgrade', 'noop'];

const Map<String, int> PacketTypeMap = const
<String, int>{
  'open': 0,
  'close': 1,
  'ping': 2,
  'pong': 3,
  'message': 4,
  'upgrade': 5,
  'noop': 6
};

class PacketParser {
  static const ERROR = const { 'type': 'error', 'data': 'parser error'};
  static String encodePacket(Map packet,
                             {supportsBinary, utf8encode = false, callback(
                                 _), bool fromClient = false}) {
    if (supportsBinary is Function) {
      callback = supportsBinary;
      supportsBinary = null;
    }

    if (utf8encode is Function) {
      callback = utf8encode;
      utf8encode = null;
    }

    if (packet['data'] is Uint8List) {
      return encodeBuffer(packet, supportsBinary, callback, fromClient: fromClient);
    } else if (packet['data'] is Map && packet['data']['buffer'] is ByteBuffer) {
      packet['data'] = (packet['data']['buffer'] as ByteBuffer).asUint8List();
      return encodeBuffer(packet, supportsBinary, callback, fromClient: fromClient);
    } else if (packet['data'] is ByteBuffer) {
      packet['data'] = (packet['data'] as ByteBuffer).asUint8List();
      return encodeBuffer(packet, supportsBinary, callback, fromClient: fromClient);
    }

    // Sending data as a utf-8 string
    var encoded = '''${PacketTypeMap[packet['type']]}''';

    // data fragment is optional
    if (packet['data'] != null) {
      encoded +=
      utf8encode == true ? WTF8.encode('''${packet['data']}''')
      : '''${packet['data']}''';
    }

    return callback('$encoded');
  }

  /**
   * Encode Buffer data
   */

  static encodeBuffer(packet, supportsBinary, callback, {fromClient = false /*use this to check whether is in client or not*/}) {
    if (!supportsBinary) {
      return encodeBase64Packet(packet, callback);
    }

    var data = packet['data'];
    // 'fromClient' is to check if the runtime is on server side or not,
    // because Dart server's websocket cannot send data with byte buffer.
    final newData = new Uint8List(data.length + 1);
    newData..setAll(0, [PacketTypeMap[packet['type']]]..length = 1)..setAll(1, data);
    if (fromClient) {
      return callback(newData.buffer);
    } else {
      return callback(newData);
    }
  }

  /**
   * Encodes a packet with binary data in a base64 string
   *
   * @param {Object} packet, has `type` and `data`
   * @return {String} base64 encoded message
   */

  static encodeBase64Packet(packet, callback) {
    var message = '''b${PacketTypeMap[packet['type']]}''';
    message += BASE64.encode(packet.data
        .toString()
        .codeUnits);
    return callback(message);
  }

  static decodePacket(dynamic data, {binaryType, bool utf8decode}) {
    var type;

    // String data
    if (data is String) {
      type = data[0];

      if (type == 'b') {
        return decodeBase64Packet(data.substr(1), binaryType);
      }

      if (utf8decode == true) {
        try {
          data = UTF8.decode(data.codeUnits);
        } catch (e) {
          return ERROR;
        }
      }
      if ('${num.parse(type)}' != type ||
          PacketTypeList[type = num.parse(type)] == null) {
        return ERROR;
      }

      if (data.length > 1) {
        return { 'type': PacketTypeList[type], 'data': data.substring(1)};
      } else {
        return { 'type': PacketTypeList[type]};
      }
    }

    // Binary data
    if (binaryType == 'arraybuffer') {
      // wrap Buffer/ArrayBuffer data into an Uint8Array
      var intArray = (data as ByteBuffer).asUint8List();
      type = intArray[0];
      return { 'type': PacketTypeList[type], 'data': intArray.sublist(0)};
    }

//    if (data instanceof ArrayBuffer) {
//      data = arrayBufferToBuffer(data);
//    }
    type = data[0];
    return { 'type': PacketTypeList[type], 'data': data.sublist(1)};
  }

  static decodeBase64Packet(String msg, String binaryType) {
    var type = PacketTypeList[msg.codeUnitAt(0)];
    var data = BASE64.decode(UTF8.decode(msg
        .substring(1)
        .codeUnits));
    if (binaryType == 'arraybuffer') {
      var abv = new Uint8List(data.length);
      for (var i = 0; i < abv.length; i++){
        abv[i] = data[i];
      }
      return { 'type': type, 'data': abv.buffer};
    }
    return { 'type': type, 'data': data};
  }

  static hasBinary(List packets) {
    return packets.any((map) {
      final data = map['data'];
      return data is ByteBuffer;
    });
  }
  static encodePayload(List packets,
                       {bool supportsBinary = false, callback(_)}) {
    if (supportsBinary && hasBinary(packets)) {
      return encodePayloadAsBinary(packets, callback);
    }

    if (packets.isEmpty) {
      return callback('0:');
    }

    var encodeOne = (packet, [doneCallback(err, _)]) {
      encodePacket(packet, supportsBinary: supportsBinary,
          utf8encode: false,
          callback: (message) {
            doneCallback(null, _setLengthHeader(message));
          });
    };

    map(packets, encodeOne, (err, results) {
      return callback(results.join(''));
    });
  }

  static _setLengthHeader(message) {
    return '${message.length}:$message';
  }

  /**
   * Async array map using after
   */
  static map(List ary, each(_, [callback(err, msg)]), done(err, results)) {
    var result = [];
    Future.wait(ary.map((e) {
      return new Future.microtask(() =>
          each(e, (err, msg) {
            result.add(msg);
          }));
    })).then((r) => done(null, result));
  }

/*
 * Decodes data when a payload is maybe expected. Possible binary contents are
 * decoded from their base64 representation
 *
 * @param {String} data, callback method
 * @api public
 */

  static decodePayload(data,
                       {bool binaryType = false, callback(err, [foo, bar])}) {
    if (data is! String) {
      return decodePayloadAsBinary(data, binaryType: binaryType, callback: callback);
    }

    if (data == '') {
      // parser error - ignoring payload
      return callback(Error, 0, 1);
    }

    var length = '',
        n,
        msg,
        packet;

    for (var i = 0, l = data.length; i < l; i++) {
      var chr = data[i];

      if (chr != ':') {
        length += chr;
        continue;
      }

      if (length.isEmpty || (length !=
          '${(n = num.parse(length, (data) => data.isEmpty ? 0 : null))}')) {
        // parser error - ignoring payload
        return callback(ERROR, 0, 1);
      }

      msg = data.substring(i + 1, i + 1 + n);

      if (length != '${msg.length}') {
        // parser error - ignoring payload
        return callback(ERROR, 0, 1);
      }

      if (msg.isNotEmpty) {
        packet = decodePacket(msg, binaryType: binaryType, utf8decode: false);

        if (ERROR['type'] == packet['type'] &&
            ERROR['data'] == packet['data']) {
          // parser error in individual packet - ignoring payload
          return callback(ERROR, 0, 1);
        }

        var more = callback(packet, i + n, l);
        if (false == more) return null;
      }

      // advance cursor
      i += n;
      length = '';
    }

    if (length.isNotEmpty) {
      // parser error - ignoring payload
      return callback(ERROR, 0, 1);
    }
  }

  static decodePayloadAsBinary(List<int> data,
                               {bool binaryType, callback(err, [foo, bar])}) {
    var bufferTail = data;
    var buffers = [];
    var i;

    while (bufferTail.length > 0) {
      var strLen = '';
      var isString = bufferTail[0] == 0;
      for (i = 1;; i++) {
        if (bufferTail[i] == 255) break;
        // 310 = char length of Number.MAX_VALUE
        if (strLen.length > 310) {
          return callback(ERROR, 0, 1);
        }
        strLen += '${bufferTail[i]}';
      }
      bufferTail = bufferTail.skip(strLen.length + 1).toList();

      var msgLength = int.parse(strLen);

      dynamic msg = bufferTail.getRange(1, msgLength + 1);
      if (isString == true) msg = new String.fromCharCodes(msg);
      buffers.add(msg);
      bufferTail = bufferTail.skip(msgLength + 1).toList();
    }

    var total = buffers.length;
    for (i = 0; i < total; i++) {
      var buffer = buffers[i];
      callback(
          decodePacket(buffer, binaryType: binaryType, utf8decode: true), i,
          total);
    }
  }

  static encodePayloadAsBinary(List packets, [callback(_)]) {
    if (packets.isEmpty) {
      return callback(new Uint8List(0));
    }

    map(packets, encodeOneBinaryPacket, (err, List results) {
      var list = [];
      results.forEach((e) => list.addAll(e));
      return callback(list);
    });
  }

  static encodeOneBinaryPacket(p, [doneCallback(err, _)]) {
    var onBinaryPacketEncode = (packet) {
      var encodingLength = '${packet.length}';
      var sizeBuffer;

      if (packet is String) {
        sizeBuffer = new Uint8List(encodingLength.length + 2);
        sizeBuffer[0] = 0; // is a string (not true binary = 0)
        for (var i = 0; i < encodingLength.length; i++) {
          sizeBuffer[i + 1] = int.parse(encodingLength[i]);
        }
        sizeBuffer[sizeBuffer.length - 1] = 255;
        return doneCallback(
            null, new List.from(sizeBuffer)..addAll(stringToBuffer(packet)));
      }

      sizeBuffer = new Uint8List(encodingLength.length + 2);
      sizeBuffer[0] = 1; // is binary (true binary = 1)
      for (var i = 0; i < encodingLength.length; i++) {
        sizeBuffer[i + 1] = int.parse(encodingLength[i]);
      }
      sizeBuffer[sizeBuffer.length - 1] = 255;

      doneCallback(null, new List.from(sizeBuffer)..addAll(packet));
    };
    encodePacket(p, supportsBinary: true,
        utf8encode: true,
        callback: onBinaryPacketEncode);
  }

  static List<int> stringToBuffer(String string) {
    var buf = new Uint8List(string.length);
    for (var i = 0, l = string.length; i < l; i++) {
      buf[i] = string.codeUnitAt(i);
    }
    return buf;
  }
}