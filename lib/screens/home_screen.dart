import 'package:flutter/material.dart';
import 'send_file_screen.dart';
import '../services/file_transfer_service.dart';
import 'dart:io';
import '../services/hash_service.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../services/download_path_service.dart';
import 'progress_screen.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'dart:typed_data';

import '../models/discovered_device.dart';
import '../services/device_info_service.dart';
import '../services/discovery_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DiscoveryService discovery = DiscoveryService();
  final FileTransferService transferService = FileTransferService();

  Map<String, String>? deviceInfo;
  Timer? _deviceCleanupTimer;

  List<DiscoveredDevice> devices = [];
  String? incomingFileName;
  int? incomingFileSize;
  String? expectedHash;

  RandomAccessFile? receivingFile;
  File? receivingTempFile;
  int receivedSize = 0;
  Future<void> _writeQueue = Future.value();

  @override
  void initState() {
    super.initState();

    loadDeviceInfo();

    _deviceCleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      removeOfflineDevices();
    });
  }

  Future<File> getUniqueFile(File file) async {
    if (!await file.exists()) {
      return file;
    }

    final path = file.path;

    final dotIndex = path.lastIndexOf('.');

    String name;
    String extension;

    if (dotIndex != -1) {
      name = path.substring(0, dotIndex);
      extension = path.substring(dotIndex);
    } else {
      name = path;
      extension = '';
    }

    int count = 1;

    while (true) {
      final candidate = File('$name($count)$extension');

      if (!await candidate.exists()) {
        return candidate;
      }

      count++;
    }
  }

  Future<void> saveReceivedFile() async {
    if (receivingFile == null) return;

    final tempPath = receivingFile!.path;

    await receivingFile!.flush();
    await receivingFile!.close();

    receivingFile = null;

    if (Platform.isAndroid) {
      final params = SaveFileDialogParams(
        sourceFilePath: tempPath,
        fileName: incomingFileName,
      );

      await FlutterFileDialog.saveFile(params: params);
    } else if (Platform.isWindows) {
      final downloadsPath = await DownloadPathService().getDownloadPath();

      File destination = File('$downloadsPath/$incomingFileName');

      destination = await getUniqueFile(destination);

      await File(tempPath).copy(destination.path);
      await File(tempPath).delete();

      print('Saved to: ${destination.path}');
    }

    print('FILE SAVED');
  }

  Future<void> loadDeviceInfo() async {
    final info = await DeviceInfoService().getDeviceInfo();

    setState(() {
      deviceInfo = info;
    });

    await discovery.startListening(onDeviceFound: onDeviceFound);

    discovery.startBroadcasting(name: info['name']!, ip: info['ip']!);
    transferService.startServer(
      onPacket: onPacketReceived,
      onFileData: (data) {
        onFileDataReceived(data);
      },
    );
  }

  void removeOfflineDevices() {
    final now = DateTime.now();

    setState(() {
      devices.removeWhere(
        (device) => now.difference(device.lastSeen).inSeconds > 10,
      );
    });
  }

  void onPacketReceived(Map<String, dynamic> packet) {
    if (packet['type'] == 'accept') {
      print('TRANSFER ACCEPTED');
      return;
    }

    if (packet['type'] == 'file_start') {
      transferService.setReceivingState();
      return;
    }
    if (packet['type'] == 'cancel_transfer') {
      handleTransferCancelled();
      return;
    }

    incomingFileName = packet['name'];
    expectedHash = packet['sha256'];
    incomingFileSize = packet['size'];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Incoming File'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(packet['name']),
              const SizedBox(height: 10),
              Text('${packet['size']} bytes'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);

                await transferService.sendReject();
              },
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                receivedSize = 0;

                final tempDir = await getTemporaryDirectory();

                File tempFile = File('${tempDir.path}/$incomingFileName');

                tempFile = await getUniqueFile(tempFile);

                incomingFileName = tempFile.uri.pathSegments.last;

                receivingTempFile = tempFile;

                receivingFile = await tempFile.open(mode: FileMode.write);
                transferService.fileName.value = incomingFileName!;

                transferService.totalBytes.value = incomingFileSize!;

                transferService.transferredBytes.value = 0;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProgressScreen(
                      isSending: false,
                      fromDevice: 'Remote Device',
                      toDevice: deviceInfo!['name']!,
                    ),
                  ),
                );

                transferService.sendAccept();
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }

  Future<void> handleTransferCancelled() async {
    try {
      await receivingFile?.close();
    } catch (_) {}

    receivingFile = null;

    try {
      if (receivingTempFile != null && await receivingTempFile!.exists()) {
        await receivingTempFile!.delete();
      }
    } catch (_) {}

    receivedSize = 0;

    transferService.transferRunning.value = false;

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    print('PARTIAL FILE DELETED');
  }

  Future<void> onFileDataReceived(List<int> data) async {
    if (receivingFile == null) return;

    _writeQueue = _writeQueue.then((_) async {
      await receivingFile!.writeFrom(data);

      receivedSize += data.length;

      if (receivedSize % (1024 * 1024) < data.length) {
        transferService.sendProgress(receivedSize);
      }

      transferService.updateReceiveProgress(
        receivedSize,
        incomingFileSize ?? 0,
      );

      print('Received $receivedSize / $incomingFileSize');

      if (incomingFileSize != null && receivedSize == incomingFileSize!) {
        await receivingFile!.flush();

        final actualHash = await HashService.calculateSha256(
          receivingTempFile!.path,
        );

        print('EXPECTED HASH: $expectedHash');
        print('ACTUAL HASH:   $actualHash');

        if (actualHash != expectedHash) {
          print('HASH MISMATCH');

          transferService.transferResult.value = TransferResult.failed;

          return;
        }

        print('HASH VERIFIED');

        await transferService.sendTransferAck();
        transferService.setIdleState();

        await Future.delayed(const Duration(milliseconds: 500));

        await saveReceivedFile();

        receivingTempFile = null;

        transferService.transferRunning.value = false;

        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (receivedSize > incomingFileSize!) {
        print(
          'ERROR: RECEIVED MORE BYTES THAN EXPECTED '
          '$receivedSize > $incomingFileSize',
        );
      }
    });

    await _writeQueue;
  }

  void onDeviceFound(Map<String, dynamic> data) {
    if (deviceInfo == null) return;

    final myIp = deviceInfo!['ip'];

    if (data['ip'] == myIp) {
      return;
    }

    final index = devices.indexWhere((d) => d.ip == data['ip']);

    setState(() {
      if (index == -1) {
        devices.add(
          DiscoveredDevice(
            name: data['name'],
            ip: data['ip'],
            lastSeen: DateTime.now(),
          ),
        );
      } else {
        devices[index].lastSeen = DateTime.now();
      }
    });
  }

  @override
  void dispose() {
    _deviceCleanupTimer?.cancel();

    discovery.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LAN Share')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: deviceInfo == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Device',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  Text('Name: ${deviceInfo!['name']}'),
                  Text('IP: ${deviceInfo!['ip']}'),

                  const SizedBox(height: 30),

                  const Text(
                    'Online Devices',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: devices.isEmpty
                        ? const Center(child: Text('No devices found'))
                        : ListView.builder(
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              final device = devices[index];

                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.phone_android),
                                  title: Text(
                                    device.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(device.ip),
                                  trailing: const Icon(Icons.arrow_forward_ios),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => SendFileScreen(
                                          deviceName: device.name,
                                          deviceIp: device.ip,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
