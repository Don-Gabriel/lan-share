import 'package:flutter/material.dart';
import 'send_file_screen.dart';
import '../services/file_transfer_service.dart';
import 'dart:io';
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

  List<DiscoveredDevice> devices = [];
  String? incomingFileName;
  int? incomingFileSize;

  RandomAccessFile? receivingFile;
  int receivedSize = 0;
  Future<void> _writeQueue = Future.value();

  @override
  void initState() {
    super.initState();
    loadDeviceInfo();
  }

  Future<void> saveReceivedFile() async {
    if (receivingFile == null) return;

    final path = receivingFile!.path;

    await receivingFile!.flush();
    await receivingFile!.close();

    receivingFile = null;

    final params = SaveFileDialogParams(
      sourceFilePath: path,
      fileName: incomingFileName,
    );

    await FlutterFileDialog.saveFile(params: params);

    print('FILE SAVED TO DOWNLOADS');
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

  void onPacketReceived(Map<String, dynamic> packet) {
    if (packet['type'] == 'accept') {
      print('TRANSFER ACCEPTED');
      return;
    }

    if (packet['type'] == 'file_start') {
      transferService.setReceivingState();
      return;
    }
    if (packet['type'] != 'file_offer') {
      return;
    }

    incomingFileName = packet['name'];
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

                final tempFile = File('${tempDir.path}/$incomingFileName');

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

      if (incomingFileSize != null && receivedSize >= incomingFileSize!) {
        await receivingFile!.flush();

        await saveReceivedFile();
        await transferService.sendComplete();

        transferService.transferRunning.value = false;

        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
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
