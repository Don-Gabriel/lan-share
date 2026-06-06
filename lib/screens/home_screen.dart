import 'package:flutter/material.dart';
import 'send_file_screen.dart';
import '../services/file_transfer_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../services/hash_service.dart';
import 'dart:async';
import 'package:flutter/physics.dart';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import '../services/download_path_service.dart';
import 'progress_screen.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../models/discovered_device.dart';
import '../services/device_info_service.dart';
import '../services/discovery_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class ReceivedBatchFile {
  final File file;
  final String relativePath;

  ReceivedBatchFile({required this.file, required this.relativePath});
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final DiscoveryService discovery = DiscoveryService();
  final FileTransferService transferService = FileTransferService();

  Map<String, String>? deviceInfo;
  Timer? _deviceCleanupTimer;
  late AnimationController _radarController;
  late AnimationController _starController;
  bool batchAccepted = false;
  int currentBatchFile = 0;
  int totalBatchFiles = 0;

  List<DiscoveredDevice> devices = [];
  String? incomingFileName;
  int? incomingFileSize;
  String? expectedHash;

  RandomAccessFile? receivingFile;
  File? receivingTempFile;
  List<ReceivedBatchFile> batchFilesToSave = [];
  int receivedSize = 0;
  String? incomingRelativePath;
  DateTime? receiveStartTime;
  Future<void> _writeQueue = Future.value();

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _starController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

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
    print('saveReceivedFile START');

    if (receivingTempFile == null) return;

    final tempPath = receivingTempFile!.path;

    if (Platform.isAndroid) {
      final params = SaveFileDialogParams(
        sourceFilePath: tempPath,
        fileName: incomingFileName,
      );

      final savePath = await FlutterFileDialog.saveFile(params: params);

      print('SAVE PATH = $savePath');
    } else if (Platform.isWindows) {
      final downloadsPath = await DownloadPathService().getDownloadPath();

      File destination = File('$downloadsPath/$incomingFileName');

      destination = await getUniqueFile(destination);

      await File(tempPath).copy(destination.path);
      await File(tempPath).delete();

      print('Saved to: ${destination.path}');
    }

    print('FILE SAVED');
    transferService.transferResult.value = TransferResult.success;
    transferService.transferRunning.value = false;
    transferService.transferredBytes.value++;
  }

  Future<void> saveBatchFilesToFolder() async {
    if (batchFilesToSave.isEmpty) {
      return;
    }

    final folderPath = await FilePicker.platform.getDirectoryPath();

    if (folderPath == null) {
      return;
    }
    print("FILES TO SAVE = ${batchFilesToSave.length}");

    for (final item in batchFilesToSave) {
      print("SAVE: ${item.relativePath}");

      final safePath = item.relativePath.replaceAll('\\', '/');

      final destination = File('$folderPath/$safePath');
      await destination.parent.create(recursive: true);

      await item.file.copy(destination.path);
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        print(receivingFile);
        await item.file.delete();
      } catch (e) {
        print('TEMP DELETE FAILED: $e');
      }
    }

    batchFilesToSave.clear();

    print('ALL FILES SAVED');
    transferService.transferResult.value = TransferResult.success;
    transferService.transferRunning.value = false;
    transferService.transferredBytes.value++;
  }

  Future<void> loadDeviceInfo() async {
    final info = await DeviceInfoService().getDeviceInfo();

    setState(() {
      deviceInfo = info;
    });

    await discovery.startListening(onDeviceFound: onDeviceFound);

    discovery.startBroadcasting(name: info['name']!, ip: info['ip']!);
    try {
      await transferService.startServer(
        onPacket: (packet) async {
          await onPacketReceived(packet);
        },
        onFileData: (data) {
          onFileDataReceived(data);
        },
      );
    } catch (e, s) {
      print(e);
      print(s);
    }
  }

  void removeOfflineDevices() {
    final now = DateTime.now();

    setState(() {
      devices.removeWhere(
        (device) => now.difference(device.lastSeen).inSeconds > 10,
      );
    });
  }

  Future<void> onPacketReceived(Map<String, dynamic> packet) async {
    if (packet['type'] == 'accept') {
      return;
    }

    if (packet['type'] == 'file_start') {
      transferService.setReceivingState();
      transferService.transferStatus.value = 'Receiving File...';

      if (incomingFileSize == 0) {
        print('ZERO BYTE FILE');

        await receivingFile?.flush();

        final actualHash = await HashService.calculateSha256(
          receivingTempFile!.path,
        );

        if (actualHash != expectedHash) {
          transferService.transferResult.value = TransferResult.failed;
          return;
        }

        await transferService.sendTransferAck();

        if (batchAccepted) {
          batchFilesToSave.add(
            ReceivedBatchFile(
              file: receivingTempFile!,
              relativePath: incomingRelativePath!,
            ),
          );
          print(
            "BATCH ADD: ${incomingRelativePath} "
            "COUNT=${batchFilesToSave.length + 1}",
          );

          if (currentBatchFile == totalBatchFiles) {
            await saveBatchFilesToFolder();

            batchAccepted = false;
          }
        } else {
          await saveReceivedFile();
        }
      }

      return;
    }
    if (packet['type'] == 'cancel_transfer') {
      handleTransferCancelled();
      return;
    }

    incomingFileName = packet['name'];
    incomingRelativePath = packet['relativePath'];
    expectedHash = packet['sha256'];
    incomingFileSize = packet['size'];

    final bool batch = packet['batch'] ?? false;
    final int fileIndex = packet['fileIndex'] ?? 1;
    final int totalFiles = packet['totalFiles'] ?? 1;
    currentBatchFile = fileIndex;
    totalBatchFiles = totalFiles;
    transferService.currentQueueIndex.value = fileIndex;
    transferService.totalQueueFiles.value = totalFiles;

    print(
      'BATCH=$batch FILE=$fileIndex/$totalFiles batchAccepted=$batchAccepted',
    );

    if (batch && batchAccepted) {
      receivedSize = 0;
      receiveStartTime = DateTime.now();

      final tempDir = await getTemporaryDirectory();

      File tempFile = File('${tempDir.path}/$incomingFileName');

      tempFile = await getUniqueFile(tempFile);

      incomingFileName = tempFile.uri.pathSegments.last;

      receivingTempFile = tempFile;

      receivingFile = await tempFile.open(mode: FileMode.write);
      receivedSize = 0;

      transferService.fileName.value = incomingFileName!;

      transferService.totalBytes.value = incomingFileSize!;

      transferService.transferredBytes.value = 0;

      if (batch) {
        batchAccepted = true;
      }

      transferService.currentQueueIndex.value = fileIndex;
      transferService.totalQueueFiles.value = totalFiles;

      transferService.sendAccept();

      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF081B3A),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0A2A5E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.file_download,
                  size: 60,
                  color: Colors.cyanAccent,
                ),

                const SizedBox(height: 15),

                Text(
                  batch ? 'Incoming Files' : 'Incoming File',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      if (batch)
                        Text(
                          '$fileIndex of $totalFiles Files',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                      if (batch) const SizedBox(height: 8),

                      Text(
                        packet['name'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        formatBytes(packet['size']),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(context);

                          await transferService.sendReject();
                        },
                        child: const Text('Reject'),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);

                          if (batch) {
                            batchAccepted = true;
                          }

                          receivedSize = 0;
                          receiveStartTime = DateTime.now();

                          final tempDir = await getTemporaryDirectory();

                          File tempFile = File(
                            '${tempDir.path}/$incomingFileName',
                          );

                          tempFile = await getUniqueFile(tempFile);

                          incomingFileName = tempFile.uri.pathSegments.last;

                          receivingTempFile = tempFile;

                          receivingFile = await tempFile.open(
                            mode: FileMode.write,
                          );

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
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String formatBytes(int bytes) {
    const double kb = 1024;
    const double mb = kb * 1024;
    const double gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    }

    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(2)} MB';
    }

    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(2)} KB';
    }

    return '$bytes B';
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

    if (!batchAccepted) {
      transferService.transferRunning.value = false;
    }
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> onFileDataReceived(List<int> data) async {
    if (receivingFile == null) return;

    _writeQueue = _writeQueue.then((_) async {
      await receivingFile!.writeFrom(data);

      receivedSize += data.length;

      if (receiveStartTime != null) {
        final elapsedSeconds = DateTime.now()
            .difference(receiveStartTime!)
            .inSeconds;

        if (elapsedSeconds > 0) {
          final bytesPerSecond = receivedSize / elapsedSeconds;

          transferService.transferSpeed.value =
              '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s';
        }
      }

      await transferService.sendProgress(receivedSize);

      transferService.updateReceiveProgress(
        receivedSize,
        incomingFileSize ?? 0,
      );

      if (receivedSize % (10 * 1024 * 1024) < data.length) {
        print('Received $receivedSize / $incomingFileSize');
      }

      if (incomingFileSize != null && receivedSize == incomingFileSize!) {
        final receiveEndTime = DateTime.now();
        transferService.transferStatus.value = 'Verifying File...';
        await receivingFile!.flush();
        await receivingFile!.close();
        receivingFile = null;

        print('VERIFY FILE: ${receivingTempFile?.path}');
        print('SIZE: $receivedSize');
        print('EXPECTED: $incomingFileSize');

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
        final seconds =
            receiveEndTime.difference(receiveStartTime!).inMilliseconds / 1000;

        if (!batchAccepted) {
          transferService.transferResult.value = TransferResult.success;
        }
        print('SENDING TRANSFER ACK');

        await transferService.sendTransferAck();

        if (!batchAccepted) {
          transferService.setIdleState();
        }

        await Future.delayed(const Duration(milliseconds: 500));
        transferService.transferStatus.value = batchAccepted
            ? 'Waiting For Remaining Files...'
            : 'Saving File...';

        print(
          'SAVE CHECK batchAccepted=$batchAccepted '
          'file=$currentBatchFile/$totalBatchFiles',
        );

        if (batchAccepted) {
          batchFilesToSave.add(
            ReceivedBatchFile(
              file: receivingTempFile!,
              relativePath: incomingRelativePath!,
            ),
          );
          print(
            "BATCH ADD: ${incomingRelativePath} "
            "COUNT=${batchFilesToSave.length + 1}",
          );

          if (currentBatchFile == totalBatchFiles) {
            print('LAST FILE RECEIVED');

            await saveBatchFilesToFolder();

            batchAccepted = false;
          }
        } else {
          print('CALLING saveReceivedFile()');

          await saveReceivedFile();

          print('saveReceivedFile() FINISHED');

          receivingTempFile = null;
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

        devices[index] = DiscoveredDevice(
          name: data['name'],
          ip: data['ip'],
          lastSeen: DateTime.now(),
        );
      }
    });
  }

  Widget buildDeviceDot(String name) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.15),
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 44 * scale,
                  height: 44 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent.withOpacity(0.15),
                  ),
                ),

                AnimatedContainer(
                  duration: const Duration(milliseconds: 1200),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent.withOpacity(0.8),
                        blurRadius: 30,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        );
      },
    );
  }

  Widget buildMyDeviceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Device',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            deviceInfo!['name']!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            deviceInfo!['ip']!,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget buildOnlineDevicesPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Online Devices (${devices.length})',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];

                return AnimatedPadding(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      title: Text(
                        device.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        device.ip,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOnlineDevicesMobile() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Online Devices (${devices.length})',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          if (devices.isEmpty)
            const Text('Searching...', style: TextStyle(color: Colors.white70)),

          ...devices.map(
            (device) => ListTile(
              leading: const Icon(
                Icons.circle,
                color: Colors.greenAccent,
                size: 14,
              ),
              title: Text(
                device.name,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                device.ip,
                style: const TextStyle(color: Colors.white70),
              ),
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
          ),
        ],
      ),
    );
  }

  Widget buildStars() {
    return AnimatedBuilder(
      animation: _starController,
      builder: (context, child) {
        return CustomPaint(
          painter: StarPainter(offset: _starController.value),
          size: Size.infinite,
        );
      },
    );
  }

  Widget buildRadar() {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;
    final radarSize = isDesktop ? 500.0 : size.width * 0.75;
    final center = radarSize / 2;
    return SizedBox(
      height: radarSize,
      width: radarSize,
      child: AnimatedBuilder(
        animation: _radarController,
        builder: (context, child) {
          return CustomPaint(
            painter: RadarPainter(
              sweepAngle: _radarController.value * 2 * math.pi,
            ),
            child: Stack(
              children: [
                for (int i = 0; i < devices.length; i++)
                  Positioned(
                    left:
                        center +
                        ((radarSize * 0.32) * math.cos((i + 1) * 1.2)) -
                        20,
                    top:
                        center +
                        ((radarSize * 0.32) * math.sin((i + 1) * 1.2)) -
                        20,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 600),
                      opacity: 1,
                      child: GestureDetector(
                        onTap: () {
                          final device = devices[i];

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
                        child: buildDeviceDot(devices[i].name),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _deviceCleanupTimer?.cancel();
    _radarController.dispose();
    _starController.dispose();

    discovery.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF081B3A),
        elevation: 0,
        title: const Text(
          'LAN Share',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      extendBodyBehindAppBar: false,
      body: Stack(
        children: [
          buildStars(),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF081B3A),
                  Color(0xFF0A2A5E),
                  Color(0xFF1565C0),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: deviceInfo == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth > 900;

                          if (!isDesktop) {
                            return SingleChildScrollView(
                              child: Column(
                                children: [
                                  const SizedBox(height: 20),

                                  Center(child: buildRadar()),

                                  const SizedBox(height: 30),

                                  buildOnlineDevicesMobile(),

                                  const SizedBox(height: 20),

                                  buildMyDeviceCard(),

                                  const SizedBox(height: 30),
                                ],
                              ),
                            );
                          }

                          return Row(
                            children: [
                              SizedBox(width: 260, child: buildMyDeviceCard()),

                              const SizedBox(width: 20),

                              Expanded(child: Center(child: buildRadar())),

                              const SizedBox(width: 20),

                              SizedBox(
                                width: 300,
                                child: buildOnlineDevicesPanel(),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final double sweepAngle;

  RadarPainter({required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final radius = size.width / 2;

    final ringPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.25)
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(
      center,
      16,
      Paint()
        ..color = Colors.blueAccent.withOpacity(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    canvas.drawCircle(center, 10, Paint()..color = Colors.blueAccent);

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }
    final linePaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.15)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      linePaint,
    );

    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      linePaint,
    );

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [Colors.transparent, Colors.blueAccent.withOpacity(0.6)],
        stops: const [0.8, 1.0],
        startAngle: sweepAngle,
        endAngle: sweepAngle + 0.8,
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final beamPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.cyanAccent.withOpacity(0.8),
          Colors.cyanAccent.withOpacity(0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      sweepAngle - 0.30,
      0.30,
      true,
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return true;
  }
}

class StarPainter extends CustomPainter {
  final double offset;

  StarPainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.15);

    for (int i = 0; i < 120; i++) {
      final x = ((i * 97) % size.width);

      final y = (((i * 43) + (offset * 50)) % size.height).toDouble();

      canvas.drawCircle(Offset(x.toDouble(), y), 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StarPainter oldDelegate) {
    return true;
  }
}
