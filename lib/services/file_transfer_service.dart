import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/transfer_file.dart';
import '../models/transfer_history_entry.dart';
import 'android_file_bridge.dart';
import 'hash_service.dart';
import 'protocol_service.dart';
import 'transfer_history_service.dart';
import 'trusted_device_service.dart';

enum TransferState { idle, receivingFile }

enum TransferResult { none, success, failed, cancelled }

class FileTransferService {
  static final FileTransferService instance = FileTransferService._internal();
  Timer? _offerTimeout;
  ServerSocket? _server;

  factory FileTransferService() {
    return instance;
  }

  FileTransferService._internal();
  Socket? _activeSocket;
  String? _targetIp;
  TransferFile? _pendingFile;
  List<TransferFile> _transferQueue = [];

  int _currentFileIndex = 0;

  bool _batchTransfer = false;
  bool _transferCancelled = false;
  DateTime? _transferStartTime;
  bool _historyWrittenForRun = false;
  String _localDeviceName = Platform.localHostname;
  String _localDeviceId = '';
  String _localDeviceIp = '';
  String _targetName = '';

  Function(List<int>)? onFileData;

  TransferState _state = TransferState.idle;

  ValueNotifier<int> transferredBytes = ValueNotifier(0);

  ValueNotifier<String> eta = ValueNotifier('--');
  ValueNotifier<String> transferSpeed = ValueNotifier('--');

  ValueNotifier<int> totalBytes = ValueNotifier(0);

  ValueNotifier<bool> transferRunning = ValueNotifier(false);

  ValueNotifier<TransferResult> transferResult = ValueNotifier(
    TransferResult.none,
  );

  ValueNotifier<bool> sending = ValueNotifier(false);

  ValueNotifier<int> currentQueueIndex = ValueNotifier(1);

  ValueNotifier<int> totalQueueFiles = ValueNotifier(1);

  ValueNotifier<String> fileName = ValueNotifier('');

  ValueNotifier<String> transferStatus = ValueNotifier('');

  ValueNotifier<String> fromDevice = ValueNotifier('');

  ValueNotifier<String> toDevice = ValueNotifier('');

  bool get isReceiving => _state == TransferState.receivingFile;

  void setLocalDevice({
    required String name,
    required String id,
    required String ip,
  }) {
    _localDeviceName = name;
    _localDeviceId = id;
    _localDeviceIp = ip;
  }

  Future<void> sendReject() async {
    if (_activeSocket == null) return;

    final packet = ProtocolService.createPacket('reject', []);

    _activeSocket!.add(packet);

    await _activeSocket!.flush();

    debugPrint('Reject sent');
  }

  Future<void> startServer({
    required Function(Map<String, dynamic>) onPacket,
    Function(List<int>)? onFileData,
  }) async {
    this.onFileData = onFileData;

    await _server?.close();

    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 55555);

    final server = _server!;

    server.listen((client) {
      debugPrint('New TCP connection from ${client.remoteAddress.address}');

      _activeSocket = client;
      final packetBuffer = BytesBuilder();

      client.listen(
        (data) {
          packetBuffer.add(data);

          final packets = ProtocolService.extractPackets(packetBuffer);

          for (final packet in packets) {
            if (packet.type == 'file_chunk') {
              onFileData?.call(packet.payload);
              continue;
            }

            if (packet.type == 'file_start') {
              onPacket({'type': 'file_start'});
              continue;
            }

            if (packet.type == 'accept') {
              onPacket({'type': 'accept'});
              continue;
            }

            if (packet.type == 'transfer_ack') {
              onPacket({'type': 'transfer_ack'});
              continue;
            }

            if (packet.type == 'reject') {
              onPacket({'type': 'reject'});
              continue;
            }

            if (packet.type == 'cancel_transfer') {
              onPacket({'type': 'cancel_transfer'});
              continue;
            }

            if (packet.type == 'file_offer') {
              try {
                final json = utf8.decode(packet.payload);

                final dataMap = jsonDecode(json) as Map<String, dynamic>;

                if (!_isValidFileOffer(dataMap)) {
                  onPacket({'type': 'invalid_offer'});
                  continue;
                }

                dataMap['type'] = 'file_offer';

                onPacket(dataMap);
              } catch (e) {
                debugPrint('Invalid file offer ignored: $e');
                onPacket({'type': 'invalid_offer'});
              }
            }
          }
        },
        onDone: () {
          debugPrint('Client disconnected');

          _activeSocket = null;
        },
        onError: (e) {
          debugPrint('Socket error: $e');

          transferResult.value = TransferResult.failed;
          transferRunning.value = false;
          sending.value = false;

          _activeSocket?.destroy();
          _activeSocket = null;
        },
      );
    });
  }

  Future<void> sendProgress(int received) async {
    if (_activeSocket == null) return;

    final payload = utf8.encode(jsonEncode({'received': received}));

    final packet = ProtocolService.createPacket('progress', payload);

    _activeSocket!.add(packet);

    await _activeSocket!.flush();
  }

  Future<void> sendComplete() async {
    if (_activeSocket == null) return;

    final packet = ProtocolService.createPacket('complete', []);

    _activeSocket!.add(packet);

    await _activeSocket!.flush();
  }

  bool _isValidFileOffer(Map<String, dynamic> data) {
    if (data['appId'] != ProtocolService.appId ||
        data['version'] != ProtocolService.protocolVersion) {
      return false;
    }

    return data['name'] is String &&
        data['size'] is int &&
        data['sha256'] is String &&
        data['batch'] is bool &&
        data['fileIndex'] is int &&
        data['totalFiles'] is int &&
        data['relativePath'] is String &&
        (data['size'] as int) >= 0 &&
        (data['fileIndex'] as int) > 0 &&
        (data['totalFiles'] as int) > 0;
  }

  Future<void> sendFileOffer({
    required String ip,
    required TransferFile file,
  }) async {
    try {
      _transferCancelled = false;
      _transferStartTime = DateTime.now();

      eta.value = '--';
      transferSpeed.value = '--';
      _pendingFile = file;

      fileName.value = file.name;

      totalBytes.value = file.size;

      transferredBytes.value = 0;

      transferRunning.value = true;

      sending.value = true;

      toDevice.value = ip;

      fromDevice.value = _localDeviceName;
      transferStatus.value = 'Processing File...';

      _targetIp = ip;

      debugPrint('Connecting to $ip...');

      _activeSocket = await Socket.connect(
        ip,
        55555,
        timeout: const Duration(seconds: 5),
      );

      final hash = await _calculateFileHash(file);

      debugPrint('SHA256: $hash');

      final currentFile = currentQueueFile;

      final jsonPacket = jsonEncode({
        'appId': ProtocolService.appId,
        'version': ProtocolService.protocolVersion,
        'name': file.name,
        'size': file.size,
        'sha256': hash,
        'batch': _batchTransfer,
        'fileIndex': currentFileNumber,
        'totalFiles': totalFilesInQueue,
        'relativePath': currentFile?.relativePath ?? file.relativePath,
        'senderName': _localDeviceName,
        'senderId': _localDeviceId,
        'senderIp': _localDeviceIp,
      });

      final framed = ProtocolService.createPacket(
        'file_offer',
        utf8.encode(jsonPacket),
      );

      _activeSocket!.add(framed);

      await _activeSocket!.flush();

      debugPrint('File offer sent');

      _offerTimeout?.cancel();

      _offerTimeout = Timer(const Duration(seconds: 30), () {
        debugPrint('TRANSFER TIMEOUT');

        transferResult.value = TransferResult.failed;

        transferRunning.value = false;

        sending.value = false;

        _activeSocket?.destroy();
        _activeSocket = null;
        unawaited(_recordSendHistory(TransferResult.failed));
      });

      final senderPacketBuffer = BytesBuilder();

      _activeSocket!.listen((data) async {
        senderPacketBuffer.add(data);

        final packets = ProtocolService.extractPackets(senderPacketBuffer);

        for (final packet in packets) {
          debugPrint('SENDER FRAME: ${packet.type}');

          if (packet.type == 'progress') {
            final progressJson = utf8.decode(packet.payload);

            final progressData =
                jsonDecode(progressJson) as Map<String, dynamic>;

            debugPrint('PROGRESS PACKET: ${progressData['received']}');

            transferredBytes.value = progressData['received'];

            continue;
          }

          if (packet.type == 'transfer_ack') {
            debugPrint('TRANSFER_ACK RECEIVED');
            debugPrint('TRANSFER VERIFIED');

            transferredBytes.value = totalBytes.value;

            _activeSocket?.destroy();
            _activeSocket = null;

            if (hasMoreFiles) {
              debugPrint(
                'QUEUE CONTINUES -> FILE ${currentFileNumber + 1}/$totalFilesInQueue',
              );

              await Future.delayed(const Duration(milliseconds: 500));

              await sendNextFileInQueue(_targetIp!);
            } else {
              debugPrint('QUEUE FINISHED');

              transferResult.value = TransferResult.success;

              transferRunning.value = false;
              transferredBytes.value++;

              sending.value = false;
              await _recordSendHistory(TransferResult.success);
              debugPrint("SETTING SUCCESS STATE");
            }

            continue;
          }

          if (packet.type == 'accept') {
            _offerTimeout?.cancel();

            debugPrint('TRANSFER ACCEPTED');
            await _trustDeviceFromAcceptPayload(packet.payload);
            transferStatus.value = 'Sending File...';

            unawaited(
              sendFileData(
                onProgress: (transferred, total) {
                  debugPrint('SEND: $transferred / $total');
                },
              ),
            );

            continue;
          }

          if (packet.type == 'reject') {
            debugPrint('TRANSFER REJECTED');

            _offerTimeout?.cancel();

            transferResult.value = TransferResult.failed;

            transferRunning.value = false;

            sending.value = false;

            transferredBytes.value++;
            await _recordSendHistory(TransferResult.failed);

            continue;
          }

          if (packet.type == 'cancel_transfer') {
            debugPrint('TRANSFER CANCELLED BY RECEIVER');

            _transferCancelled = true;
            _offerTimeout?.cancel();
            transferResult.value = TransferResult.cancelled;
            transferRunning.value = false;
            sending.value = false;
            transferredBytes.value++;
            await _recordSendHistory(TransferResult.cancelled);
            _activeSocket?.destroy();
            _activeSocket = null;

            continue;
          }
        }
      });
    } catch (e) {
      debugPrint('Connection failed: $e');
      transferResult.value = TransferResult.failed;
      transferRunning.value = false;
      sending.value = false;
      transferredBytes.value++;
      await _recordSendHistory(TransferResult.failed);
    }
  }

  Future<void> startBatchTransfer({
    required String ip,
    required String deviceName,
  }) async {
    if (_transferQueue.isEmpty) {
      return;
    }

    _historyWrittenForRun = false;
    _targetIp = ip;
    _targetName = deviceName;

    final firstFile = _transferQueue.first;

    await sendFileOffer(ip: ip, file: firstFile);
  }

  Future<void> sendNextFileInQueue(String ip) async {
    if (!hasMoreFiles) {
      return;
    }

    moveToNextFile();

    final file = currentQueueFile;

    if (file == null) {
      return;
    }

    debugPrint(
      'STARTING NEXT FILE $currentFileNumber/$totalFilesInQueue : ${file.name}',
    );

    await sendFileOffer(ip: ip, file: file);
  }

  Future<String> _calculateFileHash(TransferFile file) async {
    if (file.usesContentUri) {
      return AndroidFileBridge.calculateSha256(file.contentUri!);
    }

    return HashService.calculateSha256(file.path);
  }

  Future<void> cancelTransfer() async {
    try {
      if (_activeSocket != null) {
        final packet = ProtocolService.createPacket('cancel_transfer', []);

        _activeSocket!.add(packet);
        _transferCancelled = true;
        transferResult.value = TransferResult.cancelled;

        await _activeSocket!.flush();
      }
    } catch (_) {}

    await _recordSendHistory(TransferResult.cancelled);
    closeConnection();
  }

  Future<void> sendTransferAck() async {
    if (_activeSocket == null) return;

    final packet = ProtocolService.createPacket('transfer_ack', []);

    _activeSocket!.add(packet);

    await _activeSocket!.flush();
  }

  Future<void> sendFileData({
    Function(int transferred, int total)? onProgress,
  }) async {
    if (_activeSocket == null) return;

    final file = _pendingFile;

    if (file == null) return;

    final totalSize = file.size;

    final transferStart = DateTime.now();

    int transferred = 0;

    final startPacket = ProtocolService.createPacket('file_start', []);
    _activeSocket!.add(startPacket);

    await _activeSocket!.flush();

    const chunkSize = 1024 * 1024; // 1 MB

    if (file.usesContentUri) {
      await _sendContentUriFile(file, totalSize, onProgress);

      if (!_transferCancelled && _activeSocket != null) {
        debugPrintTransferSummary(totalSize, transferStart);
      }

      return;
    }

    final raf = await File(file.path).open();

    while (true) {
      if (_transferCancelled) {
        debugPrint('TRANSFER CANCELLED');

        await raf.close();

        return;
      }

      if (_activeSocket == null) {
        await raf.close();

        return;
      }

      final chunk = await raf.read(chunkSize);

      if (chunk.isEmpty) {
        break;
      }

      try {
        _activeSocket!.add(ProtocolService.createPacket('file_chunk', chunk));
      } catch (e) {
        debugPrint('Socket closed during transfer');

        await raf.close();

        return;
      }

      transferred += chunk.length;
      transferredBytes.value = transferred;
      totalBytes.value = totalSize;

      final elapsedSeconds = DateTime.now()
          .difference(_transferStartTime!)
          .inSeconds;

      if (elapsedSeconds > 0) {
        final bytesPerSecond = transferred / elapsedSeconds;

        final remainingBytes = totalSize - transferred;

        final etaSeconds = (remainingBytes / bytesPerSecond).round();

        eta.value = formatEta(etaSeconds);

        transferSpeed.value =
            '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s';
      }

      if (transferred % (10 * 1024 * 1024) < chunk.length) {
        onProgress?.call(transferred, totalSize);
      }
    }

    await raf.close();

    if (!_transferCancelled && _activeSocket != null) {
      await _activeSocket!.flush();

      transferStatus.value = 'Finalizing Transfer...';

      debugPrintTransferSummary(totalSize, transferStart);
    }
  }

  Future<void> _sendContentUriFile(
    TransferFile file,
    int totalSize,
    Function(int transferred, int total)? onProgress,
  ) async {
    const chunkSize = 1024 * 1024;
    final handle = await AndroidFileBridge.openRead(file.contentUri!);
    var transferred = 0;

    try {
      while (true) {
        if (_transferCancelled || _activeSocket == null) {
          return;
        }

        final chunk = await AndroidFileBridge.readChunk(handle, chunkSize);

        if (chunk.isEmpty) {
          break;
        }

        try {
          _activeSocket!.add(ProtocolService.createPacket('file_chunk', chunk));
        } catch (_) {
          debugPrint('Socket closed during transfer');
          return;
        }

        transferred += chunk.length;
        transferredBytes.value = transferred;
        totalBytes.value = totalSize;
        _updateSpeedAndEta(transferred, totalSize);

        if (transferred % (10 * 1024 * 1024) < chunk.length) {
          onProgress?.call(transferred, totalSize);
        }
      }
    } finally {
      await AndroidFileBridge.closeRead(handle);
    }

    if (!_transferCancelled && _activeSocket != null) {
      await _activeSocket!.flush();
      transferStatus.value = 'Finalizing Transfer...';
    }
  }

  void _updateSpeedAndEta(int transferred, int totalSize) {
    final startTime = _transferStartTime;

    if (startTime == null) {
      return;
    }

    final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;

    if (elapsedSeconds <= 0) {
      return;
    }

    final bytesPerSecond = transferred / elapsedSeconds;
    final remainingBytes = totalSize - transferred;
    final etaSeconds = bytesPerSecond == 0
        ? 0
        : (remainingBytes / bytesPerSecond).round();

    eta.value = formatEta(etaSeconds);
    transferSpeed.value =
        '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s';
  }

  void debugPrintTransferSummary(int totalSize, DateTime transferStart) {
    debugPrint('ALL FILE BYTES SENT');
    debugPrint('File data sent: $totalSize bytes');

    final seconds =
        DateTime.now().difference(transferStart).inMilliseconds / 1000;

    debugPrint('SEND TIME: $seconds seconds');

    if (seconds > 0) {
      debugPrint(
        'SEND SPEED: ${(totalSize / 1024 / 1024 / seconds).toStringAsFixed(2)} MB/s',
      );
    }
  }

  String formatEta(int seconds) {
    if (seconds <= 0) {
      return '0s';
    }

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return '${minutes}m ${secs}s';
    }

    return '${secs}s';
  }

  Future<void> _recordSendHistory(TransferResult result) async {
    if (_historyWrittenForRun || _transferQueue.isEmpty) {
      return;
    }

    _historyWrittenForRun = true;

    final status = switch (result) {
      TransferResult.success => 'success',
      TransferResult.cancelled => 'cancelled',
      TransferResult.failed => 'failed',
      TransferResult.none => 'unknown',
    };
    final totalSize = _transferQueue.fold<int>(
      0,
      (sum, file) => sum + file.size,
    );
    final firstFile = _transferQueue.first;

    await TransferHistoryService.instance.add(
      TransferHistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        direction: 'sent',
        status: status,
        fileName: _transferQueue.length == 1
            ? firstFile.name
            : '${_transferQueue.length} files',
        fileCount: _transferQueue.length,
        totalBytes: totalSize,
        deviceName: _targetName.isEmpty
            ? (_targetIp ?? 'Unknown')
            : _targetName,
        deviceIp: _targetIp ?? '',
        completedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _trustDeviceFromAcceptPayload(List<int> payload) async {
    if (payload.isEmpty) {
      return;
    }

    try {
      final data = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final deviceId = data['deviceId'] as String? ?? '';
      final name = data['deviceName'] as String? ?? 'Remote Device';
      final ip = data['deviceIp'] as String? ?? _targetIp ?? '';

      if (deviceId.isEmpty) {
        return;
      }

      await TrustedDeviceService.instance.trust(
        id: deviceId,
        name: name,
        ip: ip,
      );
    } catch (error) {
      debugPrint('Accept trust payload ignored: $error');
    }
  }

  Future<void> sendAccept() async {
    if (_activeSocket == null) return;

    final payload = utf8.encode(
      jsonEncode({
        'deviceName': _localDeviceName,
        'deviceId': _localDeviceId,
        'deviceIp': _localDeviceIp,
      }),
    );

    final packet = ProtocolService.createPacket('accept', payload);

    _activeSocket!.add(packet);

    await _activeSocket!.flush();

    transferRunning.value = true;

    sending.value = false;

    transferredBytes.value = 0;

    debugPrint('Accept sent');
  }

  void setTransferQueue(List<TransferFile> files) {
    _transferQueue = List.from(files);

    _currentFileIndex = 0;
    currentQueueIndex.value = 1;

    totalQueueFiles.value = files.length;

    _batchTransfer = files.length > 1;
  }

  bool get hasMoreFiles {
    return _currentFileIndex < (_transferQueue.length - 1);
  }

  TransferFile? get currentQueueFile {
    if (_transferQueue.isEmpty) {
      return null;
    }

    return _transferQueue[_currentFileIndex];
  }

  void moveToNextFile() {
    if (hasMoreFiles) {
      _currentFileIndex++;

      currentQueueIndex.value = _currentFileIndex + 1;
    }
  }

  int get totalFilesInQueue {
    return _transferQueue.length;
  }

  int get currentFileNumber {
    return _currentFileIndex + 1;
  }

  bool get isLastFileInQueue {
    return _currentFileIndex == (_transferQueue.length - 1);
  }

  void closeConnection() {
    _transferCancelled = true;
    _offerTimeout?.cancel();
    _activeSocket?.destroy();
    _activeSocket = null;
    eta.value = '--';
    transferRunning.value = false;

    sending.value = false;

    transferStatus.value = '';
    _state = TransferState.idle;
  }

  void setIdleState() {
    _state = TransferState.idle;
  }

  void setReceivingState() {
    _state = TransferState.receivingFile;
  }

  void updateReceiveProgress(int transferred, int total) {
    transferredBytes.value = transferred;

    totalBytes.value = total;
  }
}
