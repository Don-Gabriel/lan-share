import 'package:flutter/material.dart';

import '../models/transfer_history_entry.dart';
import '../services/transfer_history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const Color _background = Color(0xFFF5F7FA);
  static const Color _surface = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF172033);
  static const Color _muted = Color(0xFF667085);
  static const Color _accent = Color(0xFF0F766E);

  late Future<List<TransferHistoryEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = TransferHistoryService.instance.load();
  }

  void _reload() {
    setState(() {
      _historyFuture = TransferHistoryService.instance.load();
    });
  }

  String _formatBytes(int bytes) {
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

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return '$date $time';
  }

  Color _statusColor(String status) {
    return switch (status) {
      'success' => const Color(0xFF027A48),
      'cancelled' => const Color(0xFFB54708),
      'failed' => const Color(0xFFB42318),
      _ => _muted,
    };
  }

  IconData _directionIcon(String direction) {
    return direction == 'received' ? Icons.call_received : Icons.call_made;
  }

  Future<void> _clearHistory() async {
    await TransferHistoryService.instance.clear();
    _reload();
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
        title: const Text('Transfer History'),
        actions: [
          IconButton(
            tooltip: 'Clear history',
            onPressed: _clearHistory,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: FutureBuilder<List<TransferHistoryEntry>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? [];

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'No transfers yet',
                style: TextStyle(color: _muted, fontSize: 18),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFE6FFFA),
                      child: Icon(
                        _directionIcon(entry.direction),
                        color: _accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${entry.direction} with ${entry.deviceName} (${entry.deviceIp})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${entry.fileCount} file(s) - ${_formatBytes(entry.totalBytes)} - ${_formatDate(entry.completedAt)}',
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      entry.status,
                      style: TextStyle(
                        color: _statusColor(entry.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
