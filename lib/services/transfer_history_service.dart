import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/transfer_history_entry.dart';

class TransferHistoryService {
  static final TransferHistoryService instance =
      TransferHistoryService._internal();

  TransferHistoryService._internal();

  factory TransferHistoryService() => instance;

  static const int _maxEntries = 100;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);

    return File('${directory.path}${Platform.pathSeparator}history.json');
  }

  Future<List<TransferHistoryEntry>> load() async {
    final file = await _file();

    if (!await file.exists()) {
      return [];
    }

    try {
      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TransferHistoryEntry.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(TransferHistoryEntry entry) async {
    final entries = await load();
    final updated = [entry, ...entries].take(_maxEntries).toList();

    await _save(updated);
  }

  Future<void> clear() async {
    await _save([]);
  }

  Future<void> _save(List<TransferHistoryEntry> entries) async {
    final file = await _file();
    final data = entries.map((entry) => entry.toJson()).toList();

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }
}
