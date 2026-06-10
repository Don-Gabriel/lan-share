import 'package:flutter/material.dart';
import 'history_screen.dart';
import 'send_file_screen.dart';
import 'trusted_devices_screen.dart';
import '../services/file_transfer_service.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../services/hash_service.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import '../services/download_path_service.dart';
import 'progress_screen.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../models/discovered_device.dart';
import '../models/transfer_history_entry.dart';
import '../services/device_info_service.dart';
import '../services/discovery_service.dart';
import '../services/file_path_sanitizer.dart';
import '../services/transfer_history_service.dart';
import '../services/trusted_device_service.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  static const Color _background = Color(0xFFF5F7FA);
  static const Color _surface = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF172033);
  static const Color _muted = Color(0xFF667085);
  static const Color _accent = Color(0xFF0F766E);

  final DiscoveryService discovery = DiscoveryService();
  final FileTransferService transferService = FileTransferService();

  Map<String, String>? deviceInfo;
  Timer? _deviceCleanupTimer;
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
  String? incomingSenderName;
  String? incomingSenderIp;
  String? incomingSenderId;
  bool incomingDeviceTrusted = false;
  DateTime? receiveStartTime;
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
    debugPrint('saveReceivedFile START');

    if (receivingTempFile == null) return;

    final tempPath = receivingTempFile!.path;
    final safeFileName = FilePathSanitizer.sanitizeFileName(incomingFileName);
    String? savedPath;

    if (Platform.isAndroid) {
      final params = SaveFileDialogParams(
        sourceFilePath: tempPath,
        fileName: safeFileName,
      );

      savedPath = await FlutterFileDialog.saveFile(params: params);

      debugPrint('SAVE PATH = $savedPath');

      if (savedPath == null) {
        await File(tempPath).delete();
        await recordReceiveHistory(
          status: 'cancelled',
          fileName: safeFileName,
          fileCount: 1,
          totalBytes: incomingFileSize ?? receivedSize,
        );
        transferService.transferResult.value = TransferResult.cancelled;
        transferService.transferRunning.value = false;
        transferService.transferredBytes.value++;
        return;
      }
    } else if (Platform.isWindows) {
      final downloadsPath = await DownloadPathService().getDownloadPath();

      File destination = File('$downloadsPath/$safeFileName');

      destination = await getUniqueFile(destination);

      await File(tempPath).copy(destination.path);
      await File(tempPath).delete();
      savedPath = destination.path;

      debugPrint('Saved to: ${destination.path}');
    } else {
      await recordReceiveHistory(
        status: 'failed',
        fileName: safeFileName,
        fileCount: 1,
        totalBytes: incomingFileSize ?? receivedSize,
      );
      transferService.transferResult.value = TransferResult.failed;
      transferService.transferRunning.value = false;
      transferService.transferredBytes.value++;
      return;
    }

    debugPrint('FILE SAVED');
    await recordReceiveHistory(
      status: 'success',
      fileName: safeFileName,
      fileCount: 1,
      totalBytes: incomingFileSize ?? receivedSize,
      savedPath: savedPath,
    );
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
      for (final item in batchFilesToSave) {
        try {
          if (await item.file.exists()) {
            await item.file.delete();
          }
        } catch (_) {}
      }

      batchFilesToSave.clear();
      await recordReceiveHistory(
        status: 'cancelled',
        fileName: '$totalBatchFiles files',
        fileCount: totalBatchFiles,
        totalBytes: receivedSize,
      );
      transferService.transferResult.value = TransferResult.cancelled;
      transferService.transferRunning.value = false;
      transferService.transferredBytes.value++;
      return;
    }
    debugPrint("FILES TO SAVE = ${batchFilesToSave.length}");

    int totalSavedBytes = 0;

    for (final item in batchFilesToSave) {
      debugPrint("SAVE: ${item.relativePath}");

      final safePath = FilePathSanitizer.sanitizeRelativePath(
        item.relativePath,
      );

      File destination = File('$folderPath/$safePath');
      await destination.parent.create(recursive: true);
      destination = await getUniqueFile(destination);

      await item.file.copy(destination.path);
      totalSavedBytes += await destination.length();
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        debugPrint('$receivingFile');
        await item.file.delete();
      } catch (e) {
        debugPrint('TEMP DELETE FAILED: $e');
      }
    }

    batchFilesToSave.clear();

    debugPrint('ALL FILES SAVED');
    await recordReceiveHistory(
      status: 'success',
      fileName: '$totalBatchFiles files',
      fileCount: totalBatchFiles,
      totalBytes: totalSavedBytes,
      savedPath: folderPath,
    );
    transferService.transferResult.value = TransferResult.success;
    transferService.transferRunning.value = false;
    transferService.transferredBytes.value++;
  }

  Future<void> loadDeviceInfo() async {
    final info = await DeviceInfoService().getDeviceInfo();

    if (!mounted) {
      return;
    }

    setState(() {
      deviceInfo = info;
    });

    transferService.setLocalDevice(
      name: info['name'] ?? 'This Device',
      id: info['id'] ?? '',
      ip: info['ip'] ?? '',
    );

    await discovery.startListening(onDeviceFound: onDeviceFound);

    discovery.startBroadcasting(
      name: info['name']!,
      ip: info['ip']!,
      deviceId: info['id']!,
    );
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
      debugPrint('$e');
      debugPrint('$s');
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

  Future<void> prepareIncomingFile({
    required int fileIndex,
    required int totalFiles,
  }) async {
    receivedSize = 0;
    receiveStartTime = DateTime.now();

    final tempDir = await getTemporaryDirectory();
    final safeFileName = FilePathSanitizer.sanitizeFileName(incomingFileName);

    File tempFile = File('${tempDir.path}/$safeFileName');

    tempFile = await getUniqueFile(tempFile);

    incomingFileName = tempFile.uri.pathSegments.last;
    receivingTempFile = tempFile;
    receivingFile = await tempFile.open(mode: FileMode.write);

    transferService.fileName.value = incomingFileName!;
    transferService.totalBytes.value = incomingFileSize!;
    transferService.transferredBytes.value = 0;
    transferService.currentQueueIndex.value = fileIndex;
    transferService.totalQueueFiles.value = totalFiles;
  }

  Future<void> trustIncomingDevice() async {
    if (incomingSenderId == null || incomingSenderId!.isEmpty) {
      return;
    }

    await TrustedDeviceService.instance.trust(
      id: incomingSenderId!,
      name: incomingSenderName ?? 'Remote Device',
      ip: incomingSenderIp ?? '',
    );

    incomingDeviceTrusted = true;
  }

  Future<void> recordReceiveHistory({
    required String status,
    required String fileName,
    required int fileCount,
    required int totalBytes,
    String? savedPath,
  }) async {
    await TransferHistoryService.instance.add(
      TransferHistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        direction: 'received',
        status: status,
        fileName: fileName,
        fileCount: fileCount,
        totalBytes: totalBytes,
        deviceName: incomingSenderName ?? 'Remote Device',
        deviceIp: incomingSenderIp ?? '',
        savedPath: savedPath,
        completedAt: DateTime.now(),
      ),
    );
  }

  Future<void> onPacketReceived(Map<String, dynamic> packet) async {
    if (packet['type'] == 'accept') {
      return;
    }

    if (packet['type'] == 'file_start') {
      transferService.setReceivingState();
      transferService.transferStatus.value = 'Receiving File...';

      if (incomingFileSize == 0) {
        debugPrint('ZERO BYTE FILE');

        await receivingFile?.flush();
        await receivingFile?.close();
        receivingFile = null;

        final actualHash = await HashService.calculateSha256(
          receivingTempFile!.path,
        );

        if (actualHash != expectedHash) {
          transferService.transferResult.value = TransferResult.failed;
          transferService.transferRunning.value = false;
          transferService.transferredBytes.value++;
          await recordReceiveHistory(
            status: 'failed',
            fileName: incomingFileName ?? 'Unknown file',
            fileCount: batchAccepted ? totalBatchFiles : 1,
            totalBytes: incomingFileSize ?? 0,
          );
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
          debugPrint(
            "BATCH ADD: $incomingRelativePath "
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

    if (packet['type'] == 'invalid_offer') {
      await transferService.sendReject();
      return;
    }

    incomingFileName = FilePathSanitizer.sanitizeFileName(packet['name']);
    incomingRelativePath = FilePathSanitizer.sanitizeRelativePath(
      packet['relativePath'],
      fallback: incomingFileName ?? 'file',
    );
    expectedHash = packet['sha256'];
    incomingFileSize = packet['size'];
    incomingSenderName = packet['senderName'] as String? ?? 'Remote Device';
    incomingSenderIp = packet['senderIp'] as String? ?? '';
    incomingSenderId = packet['senderId'] as String? ?? '';
    incomingDeviceTrusted = await TrustedDeviceService.instance.isTrusted(
      incomingSenderId,
    );

    final bool batch = packet['batch'] ?? false;
    final int fileIndex = packet['fileIndex'] ?? 1;
    final int totalFiles = packet['totalFiles'] ?? 1;
    currentBatchFile = fileIndex;
    totalBatchFiles = totalFiles;
    transferService.currentQueueIndex.value = fileIndex;
    transferService.totalQueueFiles.value = totalFiles;

    debugPrint(
      'BATCH=$batch FILE=$fileIndex/$totalFiles batchAccepted=$batchAccepted',
    );

    if (batch && batchAccepted) {
      await prepareIncomingFile(fileIndex: fileIndex, totalFiles: totalFiles);

      transferService.sendAccept();

      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final trustColor = incomingDeviceTrusted
            ? _accent
            : const Color(0xFFB54708);
        final trustBackground = incomingDeviceTrusted
            ? const Color(0xFFE6FFFA)
            : const Color(0xFFFFF7E8);

        return AlertDialog(
          backgroundColor: _surface,
          surfaceTintColor: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: _border),
          ),
          icon: const Icon(
            Icons.file_download_outlined,
            color: _accent,
            size: 36,
          ),
          title: Text(batch ? 'Incoming Files' : 'Incoming File'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: trustBackground,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: trustColor),
                    ),
                    child: Text(
                      incomingDeviceTrusted
                          ? 'Trusted device'
                          : 'New device, trust on accept',
                      style: TextStyle(
                        color: trustColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.insert_drive_file_outlined,
                      color: _accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (batch)
                            Text(
                              'File $fileIndex of $totalFiles',
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (batch) const SizedBox(height: 4),
                          Text(
                            incomingFileName ?? 'Incoming file',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatBytes(incomingFileSize ?? 0),
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(context);

                await transferService.sendReject();
              },
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);

                if (batch) {
                  batchAccepted = true;
                }

                await trustIncomingDevice();
                await prepareIncomingFile(
                  fileIndex: fileIndex,
                  totalFiles: totalFiles,
                );

                if (!context.mounted) {
                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProgressScreen(
                      isSending: false,
                      fromDevice: incomingSenderName ?? 'Remote Device',
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

    if (incomingFileName != null) {
      await recordReceiveHistory(
        status: 'cancelled',
        fileName: incomingFileName!,
        fileCount: batchAccepted ? totalBatchFiles : 1,
        totalBytes: incomingFileSize ?? 0,
      );
    }

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
        debugPrint('Received $receivedSize / $incomingFileSize');
      }

      if (incomingFileSize != null && receivedSize == incomingFileSize!) {
        transferService.transferStatus.value = 'Verifying File...';
        await receivingFile!.flush();
        await receivingFile!.close();
        receivingFile = null;

        debugPrint('VERIFY FILE: ${receivingTempFile?.path}');
        debugPrint('SIZE: $receivedSize');
        debugPrint('EXPECTED: $incomingFileSize');

        final actualHash = await HashService.calculateSha256(
          receivingTempFile!.path,
        );

        debugPrint('EXPECTED HASH: $expectedHash');
        debugPrint('ACTUAL HASH:   $actualHash');

        if (actualHash != expectedHash) {
          debugPrint('HASH MISMATCH');

          transferService.transferResult.value = TransferResult.failed;
          transferService.transferRunning.value = false;
          transferService.transferredBytes.value++;
          await recordReceiveHistory(
            status: 'failed',
            fileName: incomingFileName ?? 'Unknown file',
            fileCount: batchAccepted ? totalBatchFiles : 1,
            totalBytes: incomingFileSize ?? receivedSize,
          );

          return;
        }

        debugPrint('HASH VERIFIED');

        if (!batchAccepted) {
          transferService.transferResult.value = TransferResult.success;
        }
        debugPrint('SENDING TRANSFER ACK');

        await transferService.sendTransferAck();

        if (!batchAccepted) {
          transferService.setIdleState();
        }

        await Future.delayed(const Duration(milliseconds: 500));
        transferService.transferStatus.value = batchAccepted
            ? 'Waiting For Remaining Files...'
            : 'Saving File...';

        debugPrint(
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
          debugPrint(
            "BATCH ADD: $incomingRelativePath "
            "COUNT=${batchFilesToSave.length + 1}",
          );

          if (currentBatchFile == totalBatchFiles) {
            debugPrint('LAST FILE RECEIVED');

            await saveBatchFilesToFolder();

            batchAccepted = false;
          }
        } else {
          debugPrint('CALLING saveReceivedFile()');

          await saveReceivedFile();

          debugPrint('saveReceivedFile() FINISHED');

          receivingTempFile = null;
        }
      } else if (incomingFileSize != null && receivedSize > incomingFileSize!) {
        debugPrint(
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
    final myId = deviceInfo!['id'];

    if (data['ip'] == myIp || data['deviceId'] == myId) {
      return;
    }

    final deviceId = data['deviceId'] as String? ?? data['ip'] as String;
    final index = devices.indexWhere(
      (d) => d.id == deviceId || d.ip == data['ip'],
    );

    setState(() {
      if (index == -1) {
        devices.add(
          DiscoveredDevice(
            id: deviceId,
            name: data['name'],
            ip: data['ip'],
            port: data['port'],
            lastSeen: DateTime.now(),
          ),
        );
      } else {
        devices[index].lastSeen = DateTime.now();

        devices[index] = DiscoveredDevice(
          id: deviceId,
          name: data['name'],
          ip: data['ip'],
          port: data['port'],
          lastSeen: DateTime.now(),
        );
      }
    });
  }

  Future<void> showManualConnectDialog() async {
    final ipController = TextEditingController();
    final nameController = TextEditingController(text: 'Manual Device');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connect Manually'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ipController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'IPv4 address'),
              ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Device name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final ip = ipController.text.trim();

                if (!FilePathSanitizer.isValidIpv4(ip)) {
                  return;
                }

                Navigator.pop(context, {
                  'ip': ip,
                  'name': nameController.text.trim().isEmpty
                      ? 'Manual Device'
                      : nameController.text.trim(),
                });
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );

    ipController.dispose();
    nameController.dispose();

    if (result == null || !mounted) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SendFileScreen(
          deviceName: result['name']!,
          deviceIp: result['ip']!,
        ),
      ),
    );
  }

  Widget buildMyDeviceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE6FFFA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.computer_outlined, color: _accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This device',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  deviceInfo!['name']!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(deviceInfo!['ip']!, style: const TextStyle(color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOnlineDevicesPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available devices (${devices.length})',
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 12),

          Expanded(child: buildDeviceList()),
        ],
      ),
    );
  }

  Widget buildQuickActions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Actions',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: showManualConnectDialog,
            icon: const Icon(Icons.add_link),
            label: const Text('Connect by IP'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
            label: const Text('Transfer History'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrustedDevicesScreen()),
              );
            },
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Trusted Devices'),
          ),
        ],
      ),
    );
  }

  Widget buildOnlineDevicesMobile() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available devices (${devices.length})',
            style: const TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(height: 320, child: buildDeviceList()),
        ],
      ),
    );
  }

  Widget buildDeviceList() {
    if (devices.isEmpty) {
      return const Center(
        child: Text(
          'Searching for devices on this network',
          style: TextStyle(color: _muted),
        ),
      );
    }

    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = devices[index];

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.devices_other_outlined,
              color: Color(0xFF027A48),
            ),
          ),
          title: Text(
            device.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _text, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(device.ip, style: const TextStyle(color: _muted)),
          trailing: const Icon(Icons.chevron_right),
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
        );
      },
    );
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
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'LAN Share',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Transfer history',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Manual connect',
            onPressed: showManualConnectDialog,
            icon: const Icon(Icons.add_link),
          ),
          IconButton(
            tooltip: 'Trusted devices',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrustedDevicesScreen()),
              );
            },
            icon: const Icon(Icons.verified_user),
          ),
        ],
      ),
      extendBodyBehindAppBar: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: deviceInfo == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 860;

                    if (!isDesktop) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            buildMyDeviceCard(),
                            const SizedBox(height: 12),
                            buildQuickActions(),
                            const SizedBox(height: 12),
                            buildOnlineDevicesMobile(),
                          ],
                        ),
                      );
                    }

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 340,
                              child: Column(
                                children: [
                                  buildMyDeviceCard(),
                                  const SizedBox(height: 12),
                                  buildQuickActions(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: buildOnlineDevicesPanel()),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
