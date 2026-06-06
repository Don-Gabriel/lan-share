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

  IconData getFileIcon(String fileName) {
    final name = fileName.toLowerCase();

    if (name.endsWith('.pdf')) return Icons.picture_as_pdf;

    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png')) {
      return Icons.image;
    }

    if (name.endsWith('.mp4') || name.endsWith('.mkv')) {
      return Icons.movie;
    }

    if (name.endsWith('.mp3')) {
      return Icons.music_note;
    }

    if (name.endsWith('.zip') || name.endsWith('.rar')) {
      return Icons.archive;
    }

    return Icons.insert_drive_file;
  }

  Widget buildProgressCircle(double progress) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.35),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
            ),
          ),

          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text('Progress', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildResultScreen() {
    final result = transferService.transferResult.value;

    String title;
    IconData icon;
    Color iconColor;

    if (result == TransferResult.success) {
      title = 'Transfer Completed';
      icon = Icons.check_circle;
      iconColor = Colors.greenAccent;
    } else if (result == TransferResult.cancelled) {
      title = 'Transfer Cancelled';
      icon = Icons.cancel;
      iconColor = Colors.orangeAccent;
    } else {
      title = 'Transfer Failed';
      icon = Icons.error;
      iconColor = Colors.redAccent;
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withOpacity(0.15),
              ),
              child: Icon(icon, size: 70, color: iconColor),
            ),

            const SizedBox(height: 25),

            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            ValueListenableBuilder<int>(
              valueListenable: transferService.currentQueueIndex,
              builder: (context, current, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: transferService.totalQueueFiles,
                  builder: (context, total, _) {
                    return Text(
                      '$current of $total files',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 12),

            Text(
              transferService.fileName.value,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: const Text('Back To Home'),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Send More Files'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF081B3A), Color(0xFF0A2A5E), Color(0xFF1565C0)],
          ),
        ),

        child: Padding(
          padding: const EdgeInsets.all(24),

          child: ValueListenableBuilder<int>(
            valueListenable: transferService.transferredBytes,

            builder: (context, _, __) {
              final transferred = transferService.transferredBytes.value;
              final total = transferService.totalBytes.value;

              final progress = total == 0 ? 0.0 : transferred / total;

              final remaining = (total - transferred).clamp(0, total);

              if (!transferService.transferRunning.value) {
                return buildResultScreen();
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: transferService.currentQueueIndex,
                      builder: (context, current, _) {
                        return ValueListenableBuilder<int>(
                          valueListenable: transferService.totalQueueFiles,
                          builder: (context, total, _) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'File $current of $total',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 10),

                                Text(
                                  transferService.fileName.value,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    Text(
                      'From: ${widget.fromDevice}',
                      style: const TextStyle(color: Colors.white),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'To: ${widget.toDevice}',
                      style: const TextStyle(color: Colors.white),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'File Size: ${formatBytes(total)}',
                      style: const TextStyle(color: Colors.white),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: buildProgressCircle(progress)),
                    ),
                    const SizedBox(height: 20),

                    ValueListenableBuilder<int>(
                      valueListenable: transferService.currentQueueIndex,
                      builder: (context, current, _) {
                        return ValueListenableBuilder<int>(
                          valueListenable: transferService.totalQueueFiles,
                          builder: (context, total, _) {
                            final queueProgress = total == 0
                                ? 0.0
                                : current / total;

                            return Column(
                              children: [
                                const Text(
                                  'Queue Progress',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 10),

                                LinearProgressIndicator(
                                  value: queueProgress,
                                  minHeight: 8,
                                  backgroundColor: Colors.white12,
                                  valueColor: const AlwaysStoppedAnimation(
                                    Colors.cyanAccent,
                                  ),
                                ),

                                const SizedBox(height: 8),

                                Text(
                                  '$current / $total Files',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 30),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.15),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  getFileIcon(transferService.fileName.value),
                                  color: Colors.white,
                                ),

                                const SizedBox(width: 10),

                                Flexible(
                                  child: Text(
                                    transferService.fileName.value,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 15),
                          Text(
                            'Transferred: ${formatBytes(transferred)}',
                            style: const TextStyle(color: Colors.white),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            'Remaining: ${formatBytes(remaining)}',
                            style: const TextStyle(color: Colors.white70),
                          ),

                          const SizedBox(height: 10),

                          ValueListenableBuilder<String>(
                            valueListenable: transferService.transferSpeed,
                            builder: (context, speed, _) {
                              return Text(
                                'Speed: $speed',
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 10),

                          ValueListenableBuilder<String>(
                            valueListenable: transferService.transferStatus,
                            builder: (context, status, _) {
                              return Text(
                                status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel Transfer'),
                        onPressed: () async {
                          await transferService.cancelTransfer();
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
