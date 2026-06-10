import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/transfer_file.dart';
import '../services/android_file_bridge.dart';
import '../services/device_info_service.dart';
import '../services/file_path_sanitizer.dart';
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
  static const Color _background = Color(0xFFF5F7FA);
  static const Color _surface = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF172033);
  static const Color _muted = Color(0xFF667085);
  static const Color _accent = Color(0xFF0F766E);

  final FileTransferService transferService = FileTransferService();
  final List<TransferFile> selectedFiles = [];

  bool isPicking = false;
  bool isSending = false;
  String activityLabel = '';

  int get selectedFileCount {
    return selectedFiles.where((file) => !file.isFolder).length;
  }

  int get selectedFolderCount {
    return selectedFiles.where((file) => file.isFolder).length;
  }

  int get selectedKnownSize {
    return selectedFiles
        .where((file) => !file.isFolder)
        .fold(0, (sum, file) => sum + file.size);
  }

  bool get canSend => selectedFiles.isNotEmpty && !isPicking && !isSending;

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

  String folderNameFromPath(String folderPath) {
    final normalized = folderPath.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList();

    return parts.isEmpty ? 'Selected folder' : parts.last;
  }

  IconData getFileIcon(TransferFile file) {
    if (file.isFolder) {
      return Icons.folder_outlined;
    }

    final name = file.name.toLowerCase();

    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;

    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp')) {
      return Icons.image_outlined;
    }

    if (name.endsWith('.mp4') ||
        name.endsWith('.mkv') ||
        name.endsWith('.avi')) {
      return Icons.movie_outlined;
    }

    if (name.endsWith('.mp3') || name.endsWith('.wav')) {
      return Icons.audio_file_outlined;
    }

    if (name.endsWith('.zip') ||
        name.endsWith('.rar') ||
        name.endsWith('.7z')) {
      return Icons.archive_outlined;
    }

    return Icons.insert_drive_file_outlined;
  }

  Future<void> pickFile() async {
    if (isPicking) return;

    setState(() {
      isPicking = true;
      activityLabel = 'Opening file picker...';
    });

    try {
      final files = Platform.isAndroid
          ? await AndroidFileBridge.pickFiles()
          : await pickDesktopFiles();

      if (!mounted || files.isEmpty) {
        return;
      }

      setState(() {
        selectedFiles.addAll(files);
        activityLabel = '';
      });
    } catch (error) {
      showMessage('File selection failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          isPicking = false;
          if (activityLabel == 'Opening file picker...') {
            activityLabel = '';
          }
        });
      }
    }
  }

  Future<List<TransferFile>> pickDesktopFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );

    if (result == null) {
      return [];
    }

    return result.files.where((file) => file.path != null).map((file) {
      final safeName = FilePathSanitizer.sanitizeFileName(file.name);

      return TransferFile(
        name: safeName,
        path: file.path!,
        size: file.size,
        relativePath: safeName,
      );
    }).toList();
  }

  Future<void> pickFolder() async {
    if (isPicking) return;

    setState(() {
      isPicking = true;
      activityLabel = 'Opening folder picker...';
    });

    try {
      final folder = Platform.isAndroid
          ? await AndroidFileBridge.pickFolder()
          : await pickDesktopFolder();

      if (!mounted || folder == null) {
        return;
      }

      setState(() {
        selectedFiles.add(folder);
        activityLabel = '';
      });
    } catch (error) {
      showMessage('Folder selection failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          isPicking = false;
          if (activityLabel == 'Opening folder picker...') {
            activityLabel = '';
          }
        });
      }
    }
  }

  Future<TransferFile?> pickDesktopFolder() async {
    final folderPath = await FilePicker.platform.getDirectoryPath();

    if (folderPath == null) {
      return null;
    }

    final folderName = FilePathSanitizer.sanitizeFileName(
      folderNameFromPath(folderPath),
      fallback: 'Selected folder',
    );

    return TransferFile.folder(
      name: folderName,
      path: folderPath,
      relativePath: folderName,
    );
  }

  Future<List<TransferFile>> expandSelectedItems() async {
    final queue = <TransferFile>[];

    for (final item in selectedFiles) {
      if (!item.isFolder) {
        queue.add(item);
        continue;
      }

      setState(() {
        activityLabel = 'Preparing ${item.name}...';
      });

      final files = item.usesContentUri
          ? await AndroidFileBridge.listFolderFiles(item.contentUri!, item.name)
          : await scanDesktopFolder(item.path, item.name);

      queue.addAll(files);
    }

    return queue;
  }

  Future<List<TransferFile>> scanDesktopFolder(
    String folderPath,
    String folderName,
  ) async {
    final root = Directory(folderPath);
    final files = <TransferFile>[];

    if (!await root.exists()) {
      return files;
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final relative = FilePathSanitizer.sanitizeRelativePath(
        '$folderName/${entity.path.substring(folderPath.length + 1)}',
        fallback: entity.uri.pathSegments.last,
      );

      files.add(
        TransferFile(
          name: FilePathSanitizer.sanitizeFileName(
            entity.uri.pathSegments.last,
          ),
          path: entity.path,
          size: await entity.length(),
          relativePath: relative,
        ),
      );
    }

    return files;
  }

  Future<void> sendFile() async {
    if (!canSend) return;

    setState(() {
      isSending = true;
      activityLabel = 'Preparing transfer...';
    });

    transferService.transferResult.value = TransferResult.none;
    transferService.transferRunning.value = true;
    transferService.transferStatus.value = 'Preparing transfer...';
    transferService.fileName.value = 'Preparing selection';
    transferService.totalBytes.value = 0;
    transferService.transferredBytes.value = 0;
    transferService.currentQueueIndex.value = 1;
    transferService.totalQueueFiles.value = selectedFiles.length;

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
      final info = await DeviceInfoService().getDeviceInfo();

      transferService.setLocalDevice(
        name: info['name'] ?? 'This Device',
        id: info['id'] ?? '',
        ip: info['ip'] ?? '',
      );

      final queue = await expandSelectedItems();

      if (queue.isEmpty) {
        transferService.transferResult.value = TransferResult.failed;
        transferService.transferRunning.value = false;
        transferService.transferredBytes.value++;
        showMessage('No transferable files found.');
        return;
      }

      transferService.setTransferQueue(queue);

      await transferService.startBatchTransfer(
        ip: widget.deviceIp,
        deviceName: widget.deviceName,
      );
    } catch (error) {
      transferService.transferResult.value = TransferResult.failed;
      transferService.transferRunning.value = false;
      transferService.transferredBytes.value++;
      showMessage('Transfer failed to start: $error');
    } finally {
      if (mounted) {
        setState(() {
          isSending = false;
          activityLabel = '';
        });
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget buildTargetHeader() {
    return Container(
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
            child: const Icon(Icons.devices_other, color: _accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(widget.deviceIp, style: const TextStyle(color: _muted)),
              ],
            ),
          ),
          const Icon(Icons.circle, color: Color(0xFF12B76A), size: 10),
          const SizedBox(width: 8),
          const Text(
            'Online',
            style: TextStyle(
              color: Color(0xFF027A48),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStats() {
    final sizeLabel = selectedFolderCount > 0
        ? '${formatBytes(selectedKnownSize)} + folders'
        : formatBytes(selectedKnownSize);

    return Row(
      children: [
        Expanded(child: buildStatTile('Files', '$selectedFileCount')),
        const SizedBox(width: 10),
        Expanded(child: buildStatTile('Folders', '$selectedFolderCount')),
        const SizedBox(width: 10),
        Expanded(child: buildStatTile('Size', sizeLabel)),
      ],
    );
  }

  Widget buildStatTile(String label, String value) {
    return Container(
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
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isPicking || isSending ? null : pickFile,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Add Files'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isPicking || isSending ? null : pickFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add Folder'),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Clear selection',
          onPressed: selectedFiles.isEmpty || isSending
              ? null
              : () => setState(selectedFiles.clear),
          icon: const Icon(Icons.clear_all),
        ),
      ],
    );
  }

  Widget buildSelectionList() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Text(
                  'Selection',
                  style: TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (activityLabel.isNotEmpty)
                  Flexible(
                    child: Text(
                      activityLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: selectedFiles.isEmpty
                ? const Center(
                    child: Text(
                      'No files selected',
                      style: TextStyle(color: _muted, fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: selectedFiles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = selectedFiles[index];

                      return ListTile(
                        leading: Icon(getFileIcon(file), color: _accent),
                        title: Text(
                          file.relativePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          file.isFolder
                              ? 'Folder'
                              : '${file.usesContentUri ? "Android file" : "File"} - ${formatBytes(file.size)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove',
                          onPressed: isSending
                              ? null
                              : () => setState(() {
                                  selectedFiles.removeAt(index);
                                }),
                          icon: const Icon(Icons.close),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget buildSendButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: canSend ? sendFile : null,
        icon: isSending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_outlined),
        label: Text(isSending ? 'Preparing...' : 'Send Now'),
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
        title: const Text('Send'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  buildTargetHeader(),
                  const SizedBox(height: 12),
                  buildStats(),
                  const SizedBox(height: 12),
                  buildActions(),
                  const SizedBox(height: 12),
                  Expanded(child: buildSelectionList()),
                  const SizedBox(height: 12),
                  buildSendButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
