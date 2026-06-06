import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/file_transfer_service.dart';
import 'progress_screen.dart';
import '../models/transfer_file.dart';
import 'dart:io';

class SendFileScreen extends StatefulWidget {
  final String deviceName;
  final String deviceIp;

  const SendFileScreen({
    super.key,
    required this.deviceName,
    required this.deviceIp,
  });

  @override
  State<SendFileScreen> createState() => _SendFileScreenState();
}

class _SendFileScreenState extends State<SendFileScreen> {
  List<TransferFile> selectedFiles = [];

  bool isSending = false;

  final FileTransferService transferService = FileTransferService();
  String formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;

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

  int get totalSize {
    return selectedFiles.fold(0, (sum, file) => sum + file.size);
  }

  Widget buildDeviceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue.withOpacity(0.15),
            ),
            child: const Icon(
              Icons.devices,
              color: Colors.cyanAccent,
              size: 40,
            ),
          ),

          const SizedBox(width: 20),

          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connected To',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    widget.deviceName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    widget.deviceIp,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.circle, color: Colors.greenAccent, size: 10),

                      SizedBox(width: 8),

                      Text(
                        'Online',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    '${selectedFiles.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Files', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 60, color: Colors.white12),

          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage, color: Colors.white),
                  const SizedBox(height: 8),
                  Text(
                    formatBytes(totalSize),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Total Size',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData getFileIcon(String fileName) {
    final name = fileName.toLowerCase();

    if (name.endsWith('.pdf')) return Icons.picture_as_pdf;

    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png')) {
      return Icons.image;
    }

    if (name.endsWith('.mp4') ||
        name.endsWith('.mkv') ||
        name.endsWith('.avi')) {
      return Icons.movie;
    }

    if (name.endsWith('.mp3') || name.endsWith('.wav')) {
      return Icons.music_note;
    }

    if (name.endsWith('.zip') || name.endsWith('.rar')) {
      return Icons.archive;
    }

    return Icons.insert_drive_file;
  }

  Widget buildFilesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: selectedFiles.isEmpty
          ? const Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_file, color: Colors.white38, size: 60),

                    SizedBox(height: 8),

                    Text(
                      'No files selected',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                    const SizedBox(height: 4),

                    Text(
                      'Select Files or Folder to begin transfer',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: selectedFiles.length,
              itemBuilder: (context, index) {
                final file = selectedFiles[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),

                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),

                  child: ListTile(
                    leading: Icon(
                      file.relativePath.contains('/')
                          ? Icons.folder
                          : getFileIcon(file.name),
                      color: Colors.white,
                    ),
                    title: Text(
                      file.relativePath,
                      style: const TextStyle(color: Colors.white),
                    ),

                    subtitle: Text(
                      '${file.relativePath.contains('/') ? "Folder" : "File"} • ${formatBytes(file.size)}',
                      style: const TextStyle(color: Colors.white70),
                    ),

                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          selectedFiles.removeAt(index);
                        });
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isSending ? null : pickFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Select Files'),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: ElevatedButton.icon(
            onPressed: isSending ? null : pickFolder,
            icon: const Icon(Icons.folder),
            label: const Text('Select Folder'),
          ),
        ),
      ],
    );
  }

  Widget buildSendButton() {
    return Container(
      width: double.infinity,
      height: 65,

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF3D5AFE), Color(0xFF00E5FF)],
        ),
        boxShadow: [
          BoxShadow(color: Colors.cyanAccent.withOpacity(0.4), blurRadius: 20),
        ],
      ),

      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),

        onPressed: selectedFiles.isEmpty || isSending ? null : sendFile,

        child: Text(
          isSending
              ? 'Sending...'
              : 'SEND ${selectedFiles.length} FILES • ${formatBytes(totalSize)}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result == null) return;

    final files = <TransferFile>[];

    for (final file in result.files) {
      if (file.path == null) continue;

      files.add(
        TransferFile(
          name: file.name,
          path: file.path!,
          size: file.size,
          relativePath: file.name,
        ),
      );
    }

    setState(() {
      selectedFiles = files;
    });
  }

  Future<void> sendFile() async {
    if (isSending) return;

    if (selectedFiles.isEmpty) {
      return;
    }

    setState(() {
      isSending = true;
    });

    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProgressScreen(
            isSending: true,
            fromDevice: 'This Device',
            toDevice: widget.deviceName,
          ),
        ),
      );
      transferService.setTransferQueue(selectedFiles);

      await transferService.startBatchTransfer(ip: widget.deviceIp);
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
        });
      }
    }
  }

  Future<void> pickFolder() async {
    final folderPath = await FilePicker.platform.getDirectoryPath();

    if (folderPath == null) return;

    final root = Directory(folderPath);

    final files = <TransferFile>[];

    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        final relative = entity.path
            .substring(folderPath.length + 1)
            .replaceAll('\\', '/');

        files.add(
          TransferFile(
            name: entity.uri.pathSegments.last,
            path: entity.path,
            size: await entity.length(),
            relativePath: relative,
          ),
        );
        for (final file in files) {
          print(file.relativePath);
        }
      }
    }

    setState(() {
      selectedFiles = files;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,

      appBar: AppBar(
        backgroundColor: const Color(0xFF081B3A),
        elevation: 0,

        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.08),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.3),
                  blurRadius: 12,
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                Navigator.pop(context);
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

        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),

              child: Padding(
                padding: const EdgeInsets.all(20),

                child: Column(
                  children: [
                    buildDeviceCard(),

                    const SizedBox(height: 20),

                    buildStatsCard(),

                    const SizedBox(height: 20),

                    Expanded(child: buildFilesCard()),

                    const SizedBox(height: 20),

                    buildActionButtons(),

                    const SizedBox(height: 20),

                    buildSendButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
