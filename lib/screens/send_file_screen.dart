import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/file_transfer_service.dart';
import 'progress_screen.dart';
import '../models/transfer_file.dart';
import '../models/transfer_file.dart';

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

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result == null) return;

    final files = <TransferFile>[];

    for (final file in result.files) {
      if (file.path == null) continue;

      files.add(
        TransferFile(name: file.name, path: file.path!, size: file.size),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.deviceName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deviceName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Device IP: ${widget.deviceIp}',
                  style: const TextStyle(fontSize: 16),
                ),

                const SizedBox(height: 40),

                const Text(
                  'Selected Files',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectedFiles.isEmpty)
                        const Text('No files selected')
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: selectedFiles.map((file) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(file.name),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSending ? null : pickFile,
                    child: const Text('Select File'),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedFiles.isEmpty || isSending
                        ? null
                        : sendFile,
                    child: Text(isSending ? 'Sending...' : 'Send'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
