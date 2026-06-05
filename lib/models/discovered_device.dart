class DiscoveredDevice {
  final String name;
  final String ip;
  DateTime lastSeen;

  DiscoveredDevice({
    required this.name,
    required this.ip,
    required this.lastSeen,
  });
}
