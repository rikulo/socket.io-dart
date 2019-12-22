/// socket.dart
///
/// Purpose:
///
/// Description:
///
/// History:
///    17/02/2017, Created by jumperchen
///
/// Copyright (C) 2017 Potix Corporation. All Rights Reserved.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:socket_io/src/engine/connect.dart';
import 'package:socket_io/src/engine/server.dart';
import 'package:socket_io/src/engine/transport/transports.dart';
import 'package:socket_io/src/util/event_emitter.dart';

/// Client class (abstract).
///
/// @api private
class Socket extends EventEmitter {
  static final Logger _logger = Logger('socket_io:engine.Socket');
  String id;
  Server server;
  Transport transport;
  bool upgrading;
  bool upgraded;
  String readyState;
  List<Map> writeBuffer;
  List<Function> packetsFn;
  List<Function> sentCallbackFn;
  List cleanupFn;
  SocketConnect connect;
  InternetAddress remoteAddress;
  Timer checkIntervalTimer;
  Timer upgradeTimeoutTimer;
  Timer pingTimeoutTimer;

  Socket(this.id, this.server, this.transport, this.connect) {
    upgrading = false;
    upgraded = false;
    readyState = 'opening';
    writeBuffer = [];
    packetsFn = [];
    sentCallbackFn = [];
    cleanupFn = [];

    // Cache IP since it might not be in the req later
    remoteAddress = connect.request.connectionInfo.remoteAddress;

    checkIntervalTimer = null;
    upgradeTimeoutTimer = null;
    pingTimeoutTimer = null;

    setTransport(transport);
    onOpen();
  }

  /// Called upon transport considered open.
  ///
  /// @api private

  void onOpen() {
    readyState = 'open';

    // sends an `open` packet
    transport.sid = id;
    sendPacket('open',
        data: json.encode({
          'sid': id,
          'upgrades': getAvailableUpgrades(),
          'pingInterval': server.pingInterval,
          'pingTimeout': server.pingTimeout
        }));

//    if (this.server.initialPacket != null) {
//      this.sendPacket('message', data: this.server.initialPacket);
//    }

    emit('open');
    setPingTimeout();
  }

  /// Called upon transport packet.
  ///
  /// @param {Object} packet
  /// @api private

  void onPacket(packet) {
    if ('open' == readyState) {
      // export packet event
      _logger.fine('packet');
      emit('packet', packet);

      // Reset ping timeout on any packet, incoming data is a good sign of
      // other side's liveness
      setPingTimeout();
      switch (packet['type']) {
        case 'ping':
          _logger.fine('got ping');
          sendPacket('pong');
          emit('heartbeat');
          break;

        case 'error':
          onClose('parse error');
          break;

        case 'message':
          var data = packet['data'];
          emit('data', data);
          emit('message', data);
          break;
      }
    } else {
      _logger.fine('packet received with closed socket');
    }
  }

  /// Called upon transport error.
  ///
  /// @param {Error} error object
  /// @api private
  void onError(err) {
    _logger.fine('transport error');
    onClose('transport error', err);
  }

  /// Sets and resets ping timeout timer based on client pings.
  ///
  /// @api private
  void setPingTimeout() {
    if (pingTimeoutTimer != null) {
      pingTimeoutTimer.cancel();
    }
    pingTimeoutTimer = Timer(
        Duration(milliseconds: server.pingInterval + server.pingTimeout), () {
      onClose('ping timeout');
    });
  }

  /// Attaches handlers for the given transport.
  ///
  /// @param {Transport} transport
  /// @api private
  void setTransport(Transport transport) {
    var onError = this.onError;
    var onPacket = this.onPacket;
    var flush = (_) => this.flush();
    var onClose = (_) {
      this.onClose('transport close');
    };

    this.transport = transport;
    this.transport.once('error', onError);
    this.transport.on('packet', onPacket);
    this.transport.on('drain', flush);
    this.transport.once('close', onClose);
    // this function will manage packet events (also message callbacks)
    setupSendCallback();

    cleanupFn.add(() {
      transport.off('error', onError);
      transport.off('packet', onPacket);
      transport.off('drain', flush);
      transport.off('close', onClose);
    });
  }

  /// Upgrades socket to the given transport
  ///
  /// @param {Transport} transport
  /// @api private
  void maybeUpgrade(transport) {
    _logger.fine(
        'might upgrade socket transport from ${this.transport.name} to ${transport.name}');

    upgrading = true;
    var cleanupFn = {};
    // set transport upgrade timer
    upgradeTimeoutTimer =
        Timer(Duration(milliseconds: server.upgradeTimeout), () {
      _logger.fine('client did not complete upgrade - closing transport');
      cleanupFn['cleanup']();
      if ('open' == transport.readyState) {
        transport.close();
      }
    });

    // we force a polling cycle to ensure a fast upgrade
    var check = () {
      if ('polling' == this.transport.name && this.transport.writable == true) {
        _logger.fine('writing a noop packet to polling for fast upgrade');
        this.transport.send([
          {'type': 'noop'}
        ]);
      }
    };

    var onPacket = (packet) {
      if ('ping' == packet['type'] && 'probe' == packet['data']) {
        transport.send([
          {'type': 'pong', 'data': 'probe'}
        ]);
        emit('upgrading', transport);
        if (checkIntervalTimer != null) {
          checkIntervalTimer.cancel();
        }
        checkIntervalTimer =
            Timer.periodic(Duration(milliseconds: 100), (_) => check());
      } else if ('upgrade' == packet['type'] && readyState != 'closed') {
        _logger.fine('got upgrade packet - upgrading');
        cleanupFn['cleanup']();
        this.transport.discard();
        upgraded = true;
        clearTransport();
        setTransport(transport);
        emit('upgrade', transport);
        setPingTimeout();
        flush();
        if (readyState == 'closing') {
          transport.close(() {
            this.onClose('forced close');
          });
        }
      } else {
        cleanupFn['cleanup']();
        transport.close();
      }
    };

    var onError = (err) {
      _logger.fine('client did not complete upgrade - $err');
      cleanupFn['cleanup']();
      transport.close();
      transport = null;
    };

    var onTransportClose = (_) {
      onError('transport closed');
    };

    var onClose = (_) {
      onError('socket closed');
    };

    var cleanup = () {
      upgrading = false;
      checkIntervalTimer?.cancel();
      checkIntervalTimer = null;

      upgradeTimeoutTimer?.cancel();
      upgradeTimeoutTimer = null;

      transport.off('packet', onPacket);
      transport.off('close', onTransportClose);
      transport.off('error', onError);
      off('close', onClose);
    };
    cleanupFn['cleanup'] = cleanup; // define it later
    transport.on('packet', onPacket);
    transport.once('close', onTransportClose);
    transport.once('error', onError);

    once('close', onClose);
  }

  /// Clears listeners and timers associated with current transport.
  ///
  /// @api private
  void clearTransport() {
    var cleanup;

    var toCleanUp = cleanupFn.length;

    for (var i = 0; i < toCleanUp; i++) {
      cleanup = cleanupFn.removeAt(0);
      cleanup();
    }

    // silence further transport errors and prevent uncaught exceptions
    transport.on('error', (_) {
      _logger.fine('error triggered by discarded transport');
    });

    // ensure transport won't stay open
    transport.close();

    pingTimeoutTimer?.cancel();
  }

  /// Called upon transport considered closed.
  /// Possible reasons: `ping timeout`, `client error`, `parse error`,
  /// `transport error`, `server close`, `transport close`
  void onClose(reason, [description]) {
    if ('closed' != readyState) {
      readyState = 'closed';
      pingTimeoutTimer?.cancel();
      checkIntervalTimer?.cancel();
      checkIntervalTimer = null;
      upgradeTimeoutTimer?.cancel();

      // clean writeBuffer in next tick, so developers can still
      // grab the writeBuffer on 'close' event
      scheduleMicrotask(() {
        writeBuffer = [];
      });
      packetsFn = [];
      sentCallbackFn = [];
      clearTransport();
      emit('close', [reason, description]);
    }
  }

  /// Setup and manage send callback
  ///
  /// @api private
  void setupSendCallback() {
    // the message was sent successfully, execute the callback
    var onDrain = (_) {
      if (sentCallbackFn.isNotEmpty) {
        var seqFn = sentCallbackFn[0];
        if (seqFn is Function) {
          _logger.fine('executing send callback');
          seqFn(transport);
        }
        /// else if (Array.isArray(seqFn)) {
        /// _logger.fine('executing batch send callback');
        /// for (var l = seqFn.length, i = 0; i < l; i++) {
        /// if ('function' === typeof seqFn[i]) {
        /// seqFn[i](self.transport);
        /// }
        /// }
        ///            }
      }
    };

    transport.on('drain', onDrain);

    cleanupFn.add(() {
      transport.off('drain', onDrain);
    });
  }

  /// Sends a message packet.
  ///
  /// @param {String} message
  /// @param {Object} options
  /// @param {Function} callback
  /// @return {Socket} for chaining
  /// @api public
  void send(data, options, [callback]) => write(data, options, callback);
  Socket write(data, options, [callback]) {
    sendPacket('message', data: data, options: options, callback: callback);
    return this;
  }

  /// Sends a packet.
  ///
  /// @param {String} packet type
  /// @param {String} optional, data
  /// @param {Object} options
  /// @api private
  void sendPacket(type, {data, options, callback}) {
    options = options ?? {};
    options['compress'] = false != options['compress'];

    if ('closing' != readyState && 'closed' != readyState) {
//      _logger.fine('sending packet "%s" (%s)', type, data);

      var packet = {'type': type, 'options': options};
      if (data != null) packet['data'] = data;

      // exports packetCreate event
      emit('packetCreate', packet);

      writeBuffer.add(packet);

      // add send callback to object, if defined
      if (callback != null) packetsFn.add(callback);

      flush();
    }
  }

  /// Attempts to flush the packets buffer.
  ///
  /// @api private
  void flush() {
    if ('closed' != readyState &&
        transport.writable == true &&
        writeBuffer.isNotEmpty) {
      _logger.fine('flushing buffer to transport');
      emit('flush', writeBuffer);
      server.emit('flush', [this, writeBuffer]);
      var wbuf = writeBuffer;
      writeBuffer = [];
      if (transport.supportsFraming == false) {
        sentCallbackFn.add((_) => packetsFn.forEach((f) => f(_)));
      } else {
        sentCallbackFn.addAll(packetsFn);
      }
      packetsFn = [];
      transport.send(wbuf);
      emit('drain');
      server.emit('drain', this);
    }
  }

  /// Get available upgrades for this socket.
  ///
  /// @api private
  List<dynamic> getAvailableUpgrades() {
    var availableUpgrades = [];
    var allUpgrades = server.upgrades(transport.name);
    for (var i = 0, l = allUpgrades.length; i < l; ++i) {
      var upg = allUpgrades[i];
      if (server.transports.contains(upg)) {
        availableUpgrades.add(upg);
      }
    }
    return availableUpgrades;
  }

  /// Closes the socket and underlying transport.
  ///
  /// @param {Boolean} optional, discard
  /// @return {Socket} for chaining
  /// @api public

  void close([discard = false]) {
    if ('open' != readyState) return;
    readyState = 'closing';

    if (writeBuffer.isNotEmpty) {
      once('drain', (_) => closeTransport(discard));
      return;
    }

    closeTransport(discard);
  }

  /// Closes the underlying transport.
  ///
  /// @param {Boolean} discard
  /// @api private
  void closeTransport(discard) {
    if (discard == true) transport.discard();
    transport.close(() => onClose('forced close'));
  }
}
