import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/file_transfer_service.dart';
import 'progress_screen.dart';

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
  String? selectedFile;
  String? selectedFilePath;
  int? selectedFileSize;

  bool isSending = false;

  final FileTransferService transferService = FileTransferService();

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles();

    if (result == null) return;

    setState(() {
      selectedFile = result.files.single.name;
      selectedFilePath = result.files.single.path;
      selectedFileSize = result.files.single.size;
    });
  }

  Future<void> sendFile() async {
    if (isSending) return;

    if (selectedFile == null ||
        selectedFilePath == null ||
        selectedFileSize == null) {
      return;
    }

    setState(() {
      isSending = true;
    });

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
      await transferService.sendFileOffer(
        ip: widget.deviceIp,
        fileName: selectedFile!,
        fileSize: selectedFileSize!,
        filePath: selectedFilePath!,
      );
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
                  'Selected File',
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
                      Text(selectedFile ?? 'No file selected'),
                      if (selectedFilePath != null)
                        Text(
                          selectedFilePath!,
                          style: const TextStyle(fontSize: 12),
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
                    onPressed: selectedFile == null || isSending
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
