class TrustedDevice {
  final String id;
  final String name;
  final String ip;
  final DateTime trustedAt;
  final DateTime lastSeen;

  const TrustedDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.trustedAt,
    required this.lastSeen,
  });

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();

    return TrustedDevice(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown device',
      ip: json['ip'] as String? ?? '',
      trustedAt: DateTime.tryParse(json['trustedAt'] as String? ?? '') ?? now,
      lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'trustedAt': trustedAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
    };
  }

  TrustedDevice copyWith({String? name, String? ip, DateTime? lastSeen}) {
    return TrustedDevice(
      id: id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      trustedAt: trustedAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
