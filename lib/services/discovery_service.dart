import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'file_path_sanitizer.dart';

class DiscoveryService {
  static const String appId = 'lan_share';
  static const int protocolVersion = 1;
  static const int discoveryPort = 45454;
  static const int transferPort = 55555;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  String? _deviceName;
  String? _deviceIp;
  String? _deviceId;

  Future<void> startListening({
    required Function(Map<String, dynamic>) onDeviceFound,
  }) async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;

    debugPrint('Listening for LAN Share devices on port $discoveryPort');

    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();

        if (datagram == null) return;

        try {
          final message = utf8.decode(datagram.data);

          final decoded = jsonDecode(message);

          if (decoded is! Map<String, dynamic>) {
            return;
          }

          final data = _validatedDiscoveryPacket(
            decoded,
            datagram.address.address,
          );

          if (data != null) {
            onDeviceFound(data);

            if (data['messageType'] != 'response') {
              unawaited(
                _sendPacketTo(datagram.address, messageType: 'response'),
              );
            }
          }
        } catch (e) {
          debugPrint('Ignored malformed discovery packet: $e');
        }
      }
    });
  }

  void startBroadcasting({
    required String name,
    required String ip,
    required String deviceId,
  }) {
    _broadcastTimer?.cancel();
    _deviceName = name;
    _deviceIp = ip;
    _deviceId = deviceId;

    Future<void> broadcast() async {
      await _sendPacketTo(
        InternetAddress('255.255.255.255'),
        messageType: 'announce',
      );

      String? directedBroadcast;

      try {
        directedBroadcast = await NetworkInfo().getWifiBroadcast();
      } catch (error) {
        debugPrint('Directed broadcast unavailable: $error');
      }

      if (directedBroadcast != null &&
          directedBroadcast.isNotEmpty &&
          directedBroadcast != '255.255.255.255') {
        await _sendPacketTo(
          InternetAddress(directedBroadcast),
          messageType: 'announce',
        );
      }
    }

    broadcast();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      broadcast();
    });
  }

  Future<void> _sendPacketTo(
    InternetAddress address, {
    required String messageType,
  }) async {
    final name = _deviceName;
    final ip = _deviceIp;
    final deviceId = _deviceId;

    if (name == null || ip == null || deviceId == null) {
      return;
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    final packet = jsonEncode({
      'appId': appId,
      'version': protocolVersion,
      'messageType': messageType,
      'name': name,
      'ip': ip,
      'deviceId': deviceId,
      'port': transferPort,
      'timestamp': DateTime.now().toIso8601String(),
    });

    socket.send(utf8.encode(packet), address, discoveryPort);
    socket.close();
  }

  Map<String, dynamic>? _validatedDiscoveryPacket(
    Map<String, dynamic> data,
    String senderIp,
  ) {
    if (data['appId'] != appId || data['version'] != protocolVersion) {
      return null;
    }

    final name = data['name'];
    final packetIp = data['ip'];
    final deviceId = data['deviceId'];
    final port = data['port'];
    final messageType = data['messageType'] as String? ?? 'announce';

    if (name is! String ||
        packetIp is! String ||
        deviceId is! String ||
        port is! int) {
      return null;
    }

    final ip = FilePathSanitizer.isValidIpv4(packetIp) ? packetIp : senderIp;

    if (!FilePathSanitizer.isValidIpv4(ip) || port <= 0 || port > 65535) {
      return null;
    }

    return {
      'name': name.trim().isEmpty ? 'Unknown device' : name.trim(),
      'ip': ip,
      'deviceId': deviceId,
      'port': port,
      'messageType': messageType,
    };
  }

  void dispose() {
    _broadcastTimer?.cancel();
    _socket?.close();
  }
}
