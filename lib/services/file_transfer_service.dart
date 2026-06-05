import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'hash_service.dart';
import 'dart:typed_data';
import 'protocol_service.dart';

enum TransferState { idle, receivingFile }

enum TransferResult { none, success, failed, cancelled }

class FileTransferService {
  static final FileTransferService instance = FileTransferService._internal();
  Timer? _offerTimeout;

  factory FileTransferService() {
    return instance;
  }

  FileTransferService._internal();
  Socket? _activeSocket;
  String? _pendingFilePath;
  bool _transferCancelled = false;
  DateTime? _transferStartTime;

  Function(List<int>)? onFileData;

  TransferState _state = TransferState.idle;

  ValueNotifier<int> transferredBytes = ValueNotifier(0);

  ValueNotifier<String> eta = ValueNotifier('--');

  ValueNotifier<int> totalBytes = ValueNotifier(0);

  ValueNotifier<bool> transferRunning = ValueNotifier(false);

  ValueNotifier<TransferResult> transferResult = ValueNotifier(
    TransferResult.none,
  );

  ValueNotifier<bool> sending = ValueNotifier(false);

  ValueNotifier<String> fileName = ValueNotifier('');

  ValueNotifier<String> fromDevice = ValueNotifier('');

  ValueNotifier<String> toDevice = ValueNotifier('');

  Future<void> sendReject() async {
    if (_activeSocket == null) return;

    final packet = ProtocolService.createPacket('reject', []);

    _activeSocket!.add(packet);

    await _activeSocket!.flush();

    print('Reject sent');
  }

  Future<void> startServer({
    required Function(Map<String, dynamic>) onPacket,
    Function(List<int>)? onFileData,
  }) async {
    this.onFileData = onFileData;

    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 55555);

    print('TCP Server listening on 55555');

    final packetBuffer = BytesBuilder();

    server.listen((client) {
      print('NEW TCP CONNECTION');
      print('Client connected: ${client.remoteAddress.address}');

      _activeSocket = client;

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
              final json = utf8.decode(packet.payload);

              final dataMap = jsonDecode(json) as Map<String, dynamic>;

              dataMap['type'] = 'file_offer';

              onPacket(dataMap);
            }
          }
        },
        onDone: () {
          print('Client disconnected');

          closeConnection();
        },
        onError: (e) {
          print('Socket error: $e');

          closeConnection();
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

  Future<void> sendFileOffer({
    required String ip,
    required String fileName,
    required int fileSize,
    required String filePath,
  }) async {
    try {
      _transferCancelled = false;
      _transferStartTime = DateTime.now();

      eta.value = '--';
      _pendingFilePath = filePath;

      this.fileName.value = fileName;

      totalBytes.value = fileSize;

      transferredBytes.value = 0;

      transferRunning.value = true;

      sending.value = true;

      toDevice.value = ip;

      // optional for now
      fromDevice.value = Platform.localHostname;

      print('Connecting to $ip...');

      _activeSocket = await Socket.connect(
        ip,
        55555,
        timeout: const Duration(seconds: 5),
      );

      final hash = await HashService.calculateSha256(filePath);

      print('SHA256: $hash');

      final jsonPacket = jsonEncode({
        'name': fileName,
        'size': fileSize,
        'sha256': hash,
      });

      final framed = ProtocolService.createPacket(
        'file_offer',
        utf8.encode(jsonPacket),
      );

      _activeSocket!.add(framed);

      await _activeSocket!.flush();

      print('File offer sent');

      _offerTimeout?.cancel();

      _offerTimeout = Timer(const Duration(seconds: 30), () {
        print('TRANSFER TIMEOUT');

        transferResult.value = TransferResult.failed;

        transferRunning.value = false;

        sending.value = false;

        _activeSocket?.destroy();
        _activeSocket = null;
      });

      final senderPacketBuffer = BytesBuilder();

      _activeSocket!.listen((data) {
        senderPacketBuffer.add(data);

        final packets = ProtocolService.extractPackets(senderPacketBuffer);

        for (final packet in packets) {
          print('SENDER FRAME: ${packet.type}');

          if (packet.type == 'progress') {
            final progressJson = utf8.decode(packet.payload);

            final progressData =
                jsonDecode(progressJson) as Map<String, dynamic>;

            transferredBytes.value = progressData['received'];

            continue;
          }

          if (packet.type == 'transfer_ack') {
            print('TRANSFER VERIFIED');

            transferResult.value = TransferResult.success;

            transferredBytes.value = totalBytes.value;

            transferRunning.value = false;

            sending.value = false;

            _activeSocket?.destroy();
            _activeSocket = null;

            continue;
          }

          if (packet.type == 'accept') {
            _offerTimeout?.cancel();

            print('TRANSFER ACCEPTED');

            sendFileData(
              onProgress: (transferred, total) {
                print('SEND: $transferred / $total');
              },
            );

            continue;
          }

          if (packet.type == 'reject') {
            _offerTimeout?.cancel();

            transferResult.value = TransferResult.failed;

            transferRunning.value = false;

            sending.value = false;

            continue;
          }
        }
      });
    } catch (e) {
      print('Connection failed: $e');
    }
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

    if (_pendingFilePath == null) return;

    final file = File(_pendingFilePath!);

    final totalSize = await file.length();

    int transferred = 0;

    final startPacket = ProtocolService.createPacket('file_start', []);
    _activeSocket!.add(startPacket);

    await _activeSocket!.flush();

    await for (final chunk in file.openRead()) {
      if (_transferCancelled) {
        print('TRANSFER CANCELLED');

        return;
      }

      if (_activeSocket == null) {
        return;
      }

      try {
        _activeSocket!.add(ProtocolService.createPacket('file_chunk', chunk));
      } catch (e) {
        print('Socket closed during transfer');

        return;
      }

      transferred += chunk.length;

      final elapsedSeconds = DateTime.now()
          .difference(_transferStartTime!)
          .inSeconds;

      if (elapsedSeconds > 0) {
        final bytesPerSecond = transferred / elapsedSeconds;

        final remainingBytes = totalSize - transferred;

        final etaSeconds = (remainingBytes / bytesPerSecond).round();

        eta.value = formatEta(etaSeconds);
      }

      onProgress?.call(transferred, totalSize);
    }

    if (!_transferCancelled && _activeSocket != null) {
      await _activeSocket!.flush();

      print('ALL FILE BYTES SENT');
      print('File data sent: $totalSize bytes');
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

  Future<void> sendAccept() async {
    if (_activeSocket == null) return;

    final packet = ProtocolService.createPacket('accept', []);

    _activeSocket!.add(packet);

    await _activeSocket!.flush();

    transferRunning.value = true;

    sending.value = false;

    transferredBytes.value = 0;

    print('Accept sent');
  }

  void closeConnection() {
    _transferCancelled = true;
    _offerTimeout?.cancel();
    _activeSocket?.destroy();
    _activeSocket = null;
    eta.value = '--';
    transferRunning.value = false;

    sending.value = false;

    transferredBytes.value = 0;

    totalBytes.value = 0;
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
