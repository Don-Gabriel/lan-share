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
  void dispose() {
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

  Widget buildResultScreen() {
    final result = transferService.transferResult.value;

    String title;

    IconData icon;

    if (result == TransferResult.success) {
      title = 'Transfer Completed';
      icon = Icons.check_circle;
    } else if (result == TransferResult.cancelled) {
      title = 'Transfer Cancelled';
      icon = Icons.cancel;
    } else {
      title = 'Transfer Failed';
      icon = Icons.error;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80),

          const SizedBox(height: 20),

          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 20),

          Text(
            transferService.fileName.value,
            style: const TextStyle(fontSize: 18),
          ),

          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Back To Home'),
          ),

          const SizedBox(height: 10),

          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Send More Files'),
          ),
        ],
      ),
    );
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

            if (!transferService.transferRunning.value) {
              return buildResultScreen();
            }

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
                const SizedBox(height: 10),

                ValueListenableBuilder<String>(
                  valueListenable: transferService.eta,
                  builder: (context, eta, _) {
                    return Text('ETA: $eta');
                  },
                ),

                ValueListenableBuilder<String>(
                  valueListenable: transferService.transferStatus,
                  builder: (context, status, _) {
                    return Text(
                      status,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

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
