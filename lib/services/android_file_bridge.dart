import 'dart:io';

import 'package:flutter/services.dart';

import '../models/transfer_file.dart';
import 'file_path_sanitizer.dart';

class AndroidFileBridge {
  static const MethodChannel _channel = MethodChannel('lan_share/files');

  static bool get isAvailable => Platform.isAndroid;

  static Future<List<TransferFile>> pickFiles() async {
    final result = await _channel.invokeMethod<List<dynamic>>('pickFiles');

    return _mapsToFiles(result ?? []);
  }

  static Future<TransferFile?> pickFolder() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'pickFolder',
    );

    if (result == null) {
      return null;
    }

    return _mapToFile(result);
  }

  static Future<List<TransferFile>> listFolderFiles(
    String treeUri,
    String folderName,
  ) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listFolderFiles',
      {'uri': treeUri, 'folderName': folderName},
    );

    return _mapsToFiles(result ?? []);
  }

  static Future<String> calculateSha256(String uri) async {
    final result = await _channel.invokeMethod<String>('calculateSha256', {
      'uri': uri,
    });

    return result ?? '';
  }

  static Future<int> openRead(String uri) async {
    final result = await _channel.invokeMethod<int>('openRead', {'uri': uri});

    if (result == null) {
      throw StateError('Android read handle was not created.');
    }

    return result;
  }

  static Future<Uint8List> readChunk(int handle, int chunkSize) async {
    final result = await _channel.invokeMethod<Uint8List>('readChunk', {
      'handle': handle,
      'chunkSize': chunkSize,
    });

    return result ?? Uint8List(0);
  }

  static Future<void> closeRead(int handle) async {
    await _channel.invokeMethod<void>('closeRead', {'handle': handle});
  }

  static List<TransferFile> _mapsToFiles(List<dynamic> items) {
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map(_mapToFile)
        .where((file) => file.name.isNotEmpty)
        .toList();
  }

  static TransferFile _mapToFile(Map<dynamic, dynamic> item) {
    final name = FilePathSanitizer.sanitizeFileName(
      item['name'] as String?,
      fallback: 'file',
    );
    final relativePath = FilePathSanitizer.sanitizeRelativePath(
      item['relativePath'] as String?,
      fallback: name,
    );
    final contentUri = item['uri'] as String? ?? '';
    final path = item['path'] as String? ?? '';
    final size = item['size'] is int ? item['size'] as int : 0;
    final isFolder = item['isFolder'] == true;

    if (isFolder) {
      return TransferFile.folder(
        name: name,
        path: path,
        relativePath: relativePath,
        contentUri: contentUri,
      );
    }

    return TransferFile(
      name: name,
      path: path,
      size: size,
      relativePath: relativePath,
      contentUri: contentUri,
    );
  }
}
