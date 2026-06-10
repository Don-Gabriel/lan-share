import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/trusted_device.dart';

class TrustedDeviceService {
  static final TrustedDeviceService instance = TrustedDeviceService._internal();

  TrustedDeviceService._internal();

  factory TrustedDeviceService() => instance;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);

    return File(
      '${directory.path}${Platform.pathSeparator}trusted_devices.json',
    );
  }

  Future<List<TrustedDevice>> load() async {
    final file = await _file();

    if (!await file.exists()) {
      return [];
    }

    try {
      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TrustedDevice.fromJson)
          .where((device) => device.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isTrusted(String? id) async {
    if (id == null || id.isEmpty) {
      return false;
    }

    final devices = await load();

    return devices.any((device) => device.id == id);
  }

  Future<void> trust({
    required String id,
    required String name,
    required String ip,
  }) async {
    if (id.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final devices = await load();
    final index = devices.indexWhere((device) => device.id == id);

    if (index == -1) {
      devices.insert(
        0,
        TrustedDevice(
          id: id,
          name: name,
          ip: ip,
          trustedAt: now,
          lastSeen: now,
        ),
      );
    } else {
      devices[index] = devices[index].copyWith(
        name: name,
        ip: ip,
        lastSeen: now,
      );
    }

    await _save(devices);
  }

  Future<void> remove(String id) async {
    final devices = await load();
    devices.removeWhere((device) => device.id == id);

    await _save(devices);
  }

  Future<void> _save(List<TrustedDevice> devices) async {
    final file = await _file();
    final data = devices.map((device) => device.toJson()).toList();

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }
}
