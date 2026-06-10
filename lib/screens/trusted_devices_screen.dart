import 'package:flutter/material.dart';

import '../models/trusted_device.dart';
import '../services/trusted_device_service.dart';

class TrustedDevicesScreen extends StatefulWidget {
  const TrustedDevicesScreen({super.key});

  @override
  State<TrustedDevicesScreen> createState() => _TrustedDevicesScreenState();
}

class _TrustedDevicesScreenState extends State<TrustedDevicesScreen> {
  static const Color _background = Color(0xFFF5F7FA);
  static const Color _surface = Colors.white;
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _text = Color(0xFF172033);
  static const Color _muted = Color(0xFF667085);
  static const Color _accent = Color(0xFF0F766E);
  static const Color _danger = Color(0xFFB42318);

  late Future<List<TrustedDevice>> _devicesFuture;

  @override
  void initState() {
    super.initState();
    _devicesFuture = TrustedDeviceService.instance.load();
  }

  void _reload() {
    setState(() {
      _devicesFuture = TrustedDeviceService.instance.load();
    });
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _remove(String id) async {
    await TrustedDeviceService.instance.remove(id);
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
        title: const Text('Trusted Devices'),
      ),
      body: FutureBuilder<List<TrustedDevice>>(
        future: _devicesFuture,
        builder: (context, snapshot) {
          final devices = snapshot.data ?? [];

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (devices.isEmpty) {
            return Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                constraints: const BoxConstraints(maxWidth: 460),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: _accent,
                      size: 40,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No trusted devices yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Devices are trusted automatically when a transfer is accepted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final device = devices[index];

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE6FFFA),
                      child: Icon(Icons.verified_user_outlined, color: _accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            device.ip,
                            style: const TextStyle(color: _muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Trusted ${_formatDate(device.trustedAt)}',
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove trusted device',
                      onPressed: () => _remove(device.id),
                      icon: const Icon(Icons.delete_outline, color: _danger),
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
