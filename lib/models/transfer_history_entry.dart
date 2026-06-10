class TransferHistoryEntry {
  final String id;
  final String direction;
  final String status;
  final String fileName;
  final int fileCount;
  final int totalBytes;
  final String deviceName;
  final String deviceIp;
  final String? savedPath;
  final DateTime completedAt;

  const TransferHistoryEntry({
    required this.id,
    required this.direction,
    required this.status,
    required this.fileName,
    required this.fileCount,
    required this.totalBytes,
    required this.deviceName,
    required this.deviceIp,
    required this.completedAt,
    this.savedPath,
  });

  factory TransferHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TransferHistoryEntry(
      id: json['id'] as String? ?? '',
      direction: json['direction'] as String? ?? 'sent',
      status: json['status'] as String? ?? 'success',
      fileName: json['fileName'] as String? ?? 'Unknown file',
      fileCount: json['fileCount'] as int? ?? 1,
      totalBytes: json['totalBytes'] as int? ?? 0,
      deviceName: json['deviceName'] as String? ?? 'Unknown device',
      deviceIp: json['deviceIp'] as String? ?? '',
      savedPath: json['savedPath'] as String?,
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'direction': direction,
      'status': status,
      'fileName': fileName,
      'fileCount': fileCount,
      'totalBytes': totalBytes,
      'deviceName': deviceName,
      'deviceIp': deviceIp,
      'savedPath': savedPath,
      'completedAt': completedAt.toIso8601String(),
    };
  }
}
