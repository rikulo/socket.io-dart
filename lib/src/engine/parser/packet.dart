/** 
 * packet.dart
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
class Packet {
  String type;
  dynamic data;
  Map options;
  Packet(this.type, this.data, this.options);
  factory Packet.fromJSON(Map json) {
    return new Packet(json['type'], json['data'], json['options']);
  }
}