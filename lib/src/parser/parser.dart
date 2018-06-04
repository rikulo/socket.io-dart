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
import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:socket_io/src/parser/binary.dart';
import 'package:socket_io/src/util/event_emitter.dart';

const int CONNECT = 0;
const int DISCONNECT = 1;
const int EVENT = 2;
const int ACK = 3;
const int ERROR = 4;
const int BINARY_EVENT = 5;
const int BINARY_ACK = 6;

/**
 * A socket.io Encoder instance
 *
 * @api public
 */

List<String> PacketTypes = <String> [
'CONNECT',
'DISCONNECT',
'EVENT',
'ACK',
'ERROR',
'BINARY_EVENT',
'BINARY_ACK'
];

class Encoder {

  static final Logger _logger = new Logger('socket_io:parser.Encoder');

  /**
   * Encode a packet as a single string if non-binary, or as a
   * buffer sequence, depending on packet type.
   *
   * @param {Object} obj - packet object
   * @param {Function} callback - function to handle encodings (likely engine.write)
   * @return Calls callback with Array of encodings
   * @api public
   */

  encode(obj, callback) {
    _logger.fine('encoding packet $obj');

    if (BINARY_EVENT == obj['type'] || BINARY_ACK == obj['type']) {
      encodeAsBinary(obj, callback);
    } else {
      var encoding = encodeAsString(obj);
      callback([encoding]);
    }
  }

  /**
   * Encode packet as string.
   *
   * @param {Object} packet
   * @return {String} encoded
   * @api private
   */

  static String encodeAsString(obj) {
    // first is type
    var str = '${obj['type']}';

    // attachments if we have them
  if (BINARY_EVENT == obj['type'] || BINARY_ACK == obj['type']) {
    str += '${obj['attachments']}-';
  }

    // if we have a namespace other than `/`
    // we append it followed by a comma `,`
    if (obj['nsp'] != null && '/' != obj['nsp']) {
      str += obj['nsp'] + ',';
    }

    // immediately followed by the id
    if (null != obj['id']) {
      str += '${obj['id']}';
    }

    // json data
    if (null != obj['data']) {
      str += JSON.encode(obj['data']);
    }

    _logger.fine('encoded $obj as $str');
    return str;
  }

/**
 * Encode packet as 'buffer sequence' by removing blobs, and
 * deconstructing packet into object with placeholders and
 * a list of buffers.
 *
 * @param {Object} packet
 * @return {Buffer} encoded
 * @api private
 */

static encodeAsBinary(obj, callback) {

  var writeEncoding = (bloblessData) {
    var deconstruction = Binary.deconstructPacket(bloblessData);
    var pack = encodeAsString(deconstruction['packet']);
    var buffers = deconstruction['buffers'];

    // add packet info to beginning of data list
    callback([pack]..addAll(buffers)); // write all the buffers
  };
//
//  binary.removeBlobs(obj, writeEncoding);
  writeEncoding(obj);
}
}

/**
 * A socket.io Decoder instance
 *
 * @return {Object} decoder
 * @api public
 */
class Decoder extends EventEmitter {
  dynamic reconstructor = null;

  /**
   * Decodes an ecoded packet string into packet JSON.
   *
   * @param {String} obj - encoded packet
   * @return {Object} packet
   * @api public
   */
  add(obj) {
    var packet;
    if (obj is String) {
      packet = decodeString(obj);
      if (BINARY_EVENT == packet['type'] ||
          BINARY_ACK == packet['type']) { // binary packet's json
        this.reconstructor = new BinaryReconstructor(packet);

        // no attachments, labeled binary but no binary data to follow
        if (this.reconstructor.reconPack['attachments'] == 0) {
          this.emit('decoded', packet);
        }
      } else { // non-binary full packet
        this.emit('decoded', packet);
      }
    } else if (obj is ByteBuffer || obj is Uint8List ||
        obj is Map && obj['base64'] != null) { // raw binary data
      if (this.reconstructor == null) {
        throw new UnsupportedError(
            'got binary data when not reconstructing a packet');
      } else {
        packet = this.reconstructor.takeBinaryData(obj);
        if (packet != null) { // received final buffer
          this.reconstructor = null;
          this.emit('decoded', packet);
        }
      }
    } else {
      throw new UnsupportedError('Unknown type: ' + obj);
    }
  }

  /**
   * Decode a packet String (JSON data)
   *
   * @param {String} str
   * @return {Object} packet
   * @api private
   */

  static decodeString(String str) {
    var i = 0;
    var endLen = str.length - 1;
    // look up type
    var p = <String, dynamic> {
      'type': num.parse(str[0])
    };

    if (null == PacketTypes[p['type']]) return error();

    // look up attachments if type binary
    if (BINARY_EVENT == p['type'] || BINARY_ACK == p['type']) {
      var buf = '';
      while (str[++i] != '-') {
        buf += str[i];
        if (i == endLen) break;
      }
      if (buf != '${num.parse(buf, (_) => -1)}' || str[i] != '-') {
        throw new ArgumentError('Illegal attachments');
      }
      p['attachments'] = num.parse(buf);
    }

    // look up namespace (if any)
    if (str.length > i + 1 && '/' == str[i + 1]) {
      p['nsp'] = '';
      while (++i > 0) {
        var c = str[i];
        if (',' == c) break;
        p['nsp'] += c;
        if (i == endLen) break;
      }
    } else {
      p['nsp'] = '/';
    }

    // look up id
    var next = i < endLen - 1 ? str[i + 1] : null;
    if (next?.isNotEmpty == true && '${num.parse(next, (e) => null)}' == next) {
    p['id'] = '';
    while (++i > 0) {
      var c = str[i];
      if (null == c || '${num.parse(c, (e) => null)}' != c ) {
        --i;
        break;
      }
      p['id'] += str[i];
      if (i == endLen - 1) break;
    }
//    p['id'] = p['id'];
    }

    // look up json data
    if (i < endLen - 1 && str[++i]?.isNotEmpty) {
      p = tryParse(p, str.substring(i));
    }

//    debug('decoded %s as %j', str, p);
    return p;
  }


  static tryParse(p, str) {
    try {
      p['data'] = JSON.decode(str);
    } catch(e){
      return error();
    }
    return p;
  }


/**
 * Deallocates a parser's resources
 *
 * @api public
 */

  destroy() {
    if (this.reconstructor != null) {
      this.reconstructor.finishedReconstruction();
    }
  }
}

/**
 * A manager of a binary event's 'buffer sequence'. Should
 * be constructed whenever a packet of type BINARY_EVENT is
 * decoded.
 *
 * @param {Object} packet
 * @return {BinaryReconstructor} initialized reconstructor
 * @api private
 */
class BinaryReconstructor {
  Map reconPack;
  List buffers;
  BinaryReconstructor(packet) {
    this.reconPack = packet;
    this.buffers = [];
  }

  /**
   * Method to be called when binary data received from connection
   * after a BINARY_EVENT packet.
   *
   * @param {Buffer | ArrayBuffer} binData - the raw binary data received
   * @return {null | Object} returns null if more binary data is expected or
   *   a reconstructed packet object if all buffers have been received.
   * @api private
   */
  takeBinaryData(binData) {
    this.buffers.add(binData);
    if (this.buffers.length ==
        this.reconPack['attachments']) { // done with buffer list
      var packet = Binary.reconstructPacket(this.reconPack, this.buffers);
      this.finishedReconstruction();
      return packet;
    }
    return null;
  }

  /** Cleans up binary packet reconstruction variables.
   *
   * @api private
   */
  void finishedReconstruction() {
    this.reconPack = null;
    this.buffers = [];
  }
}

Map error() {
  return {
    'type': ERROR,
    'data': 'parser error'
  };
}