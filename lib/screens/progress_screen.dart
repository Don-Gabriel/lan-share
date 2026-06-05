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
  final FileTransferService transferService = FileTransferService();

  @override
  void initState() {
    super.initState();

    transferService.transferRunning.addListener(_onTransferStateChanged);
  }

  void _onTransferStateChanged() {
    if (!transferService.transferRunning.value && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    transferService.transferRunning.removeListener(_onTransferStateChanged);

    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
        title: Text(widget.isSending ? 'Sending File' : 'Receiving File'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<int>(
          valueListenable: transferService.transferredBytes,
          builder: (context, transferred, _) {
            final total = transferService.totalBytes.value;

            final progress = total == 0 ? 0.0 : transferred / total;

            final remaining = (total - transferred).clamp(0, total);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transferService.fileName.value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 30),

                Text('From: ${widget.fromDevice}'),

                const SizedBox(height: 10),

                Text('To: ${widget.toDevice}'),

                const SizedBox(height: 25),

                Text('File Size: ${formatBytes(total)}'),

                const SizedBox(height: 10),

                Text('Transferred: ${formatBytes(transferred)}'),

                const SizedBox(height: 10),

                Text('Remaining: ${formatBytes(remaining)}'),

                const SizedBox(height: 30),

                LinearProgressIndicator(value: progress, minHeight: 12),

                const SizedBox(height: 15),

                Center(
                  child: Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel Transfer'),
                  onPressed: () async {
                    await transferService.cancelTransfer();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
