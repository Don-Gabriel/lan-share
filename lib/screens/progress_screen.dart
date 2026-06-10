import 'package:flutter/material.dart';

import '../services/file_transfer_service.dart';

class ProgressScreen extends StatefulWidget {
  final bool isSending;
  final String fromDevice;
  final String toDevice;

  const ProgressScreen({
    super.key,
    required this.isSending,
    required this.fromDevice,
    required this.toDevice,
  });

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  static const Color _background = Color(0xFFF5F7FA);
  static const Color _surface = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF172033);
  static const Color _muted = Color(0xFF667085);
  static const Color _accent = Color(0xFF0F766E);

  final FileTransferService transferService = FileTransferService();

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

  IconData getFileIcon(String fileName) {
    final name = fileName.toLowerCase();

    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png')) {
      return Icons.image_outlined;
    }
    if (name.endsWith('.mp4') || name.endsWith('.mkv')) {
      return Icons.movie_outlined;
    }
    if (name.endsWith('.mp3')) return Icons.audio_file_outlined;
    if (name.endsWith('.zip') || name.endsWith('.rar')) {
      return Icons.archive_outlined;
    }

    return Icons.insert_drive_file_outlined;
  }

  Widget buildResultScreen() {
    final result = transferService.transferResult.value;

    final (title, icon, color) = switch (result) {
      TransferResult.success => (
        'Transfer completed',
        Icons.check_circle_outline,
        const Color(0xFF027A48),
      ),
      TransferResult.cancelled => (
        'Transfer cancelled',
        Icons.cancel_outlined,
        const Color(0xFFB54708),
      ),
      _ => ('Transfer failed', Icons.error_outline, const Color(0xFFB42318)),
    };

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _text,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int>(
              valueListenable: transferService.currentQueueIndex,
              builder: (context, current, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: transferService.totalQueueFiles,
                  builder: (context, total, _) {
                    return Text(
                      '$current of $total files',
                      style: const TextStyle(color: _muted),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              transferService.fileName.value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Back To Home'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Send More'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildMetric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildProgressBody(int transferred, int total) {
    final progress = total == 0 ? 0.0 : (transferred / total).clamp(0.0, 1.0);
    final remaining = (total - transferred).clamp(0, total);

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: transferService.currentQueueIndex,
                      builder: (context, current, _) {
                        return ValueListenableBuilder<int>(
                          valueListenable: transferService.totalQueueFiles,
                          builder: (context, queueTotal, _) {
                            return Text(
                              'File $current of $queueTotal',
                              style: const TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          getFileIcon(transferService.fileName.value),
                          color: _accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            transferService.fileName.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _text,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(8),
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation(_accent),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  buildMetric('Transferred', formatBytes(transferred)),
                  const SizedBox(width: 10),
                  buildMetric('Remaining', formatBytes(remaining)),
                  const SizedBox(width: 10),
                  buildMetric('Total', formatBytes(total)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.fromDevice} -> ${widget.toDevice}',
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: transferService.transferSpeed,
                      builder: (context, speed, _) {
                        return Text(
                          'Speed: $speed',
                          style: const TextStyle(color: _muted),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<String>(
                      valueListenable: transferService.eta,
                      builder: (context, eta, _) {
                        return Text(
                          'ETA: $eta',
                          style: const TextStyle(color: _muted),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<String>(
                      valueListenable: transferService.transferStatus,
                      builder: (context, status, _) {
                        return Text(
                          status,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel Transfer'),
                  onPressed: () async {
                    await transferService.cancelTransfer();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
        title: Text(widget.isSending ? 'Sending' : 'Receiving'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<int>(
          valueListenable: transferService.transferredBytes,
          builder: (context, _, _) {
            final transferred = transferService.transferredBytes.value;
            final total = transferService.totalBytes.value;

            if (!transferService.transferRunning.value) {
              return buildResultScreen();
            }

            return buildProgressBody(transferred, total);
          },
        ),
      ),
    );
  }
}
