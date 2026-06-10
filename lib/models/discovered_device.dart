class DiscoveredDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  DateTime lastSeen;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });
}
