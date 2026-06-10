import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DeviceInfoService {
  Future<Map<String, String>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final networkInfo = NetworkInfo();

    String deviceName = 'Unknown Device';
    String ipAddress = 'Unknown IP';

    try {
      if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceName = windowsInfo.computerName;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model;
      }

      ipAddress = await networkInfo.getWifiIP() ?? 'No IP Found';
    } catch (e) {
      debugPrint('Device info lookup failed: $e');
    }

    final idSource = [
      Platform.operatingSystem,
      Platform.localHostname,
      deviceName,
    ].join('|');
    final deviceId = sha256
        .convert(utf8.encode(idSource))
        .toString()
        .substring(0, 16);

    return {'name': deviceName, 'ip': ipAddress, 'id': deviceId};
  }
}
