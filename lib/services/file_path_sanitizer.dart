class FilePathSanitizer {
  static final RegExp _unsafeFileChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  static String sanitizeFileName(String? value, {String fallback = 'file'}) {
    final raw = value?.trim() ?? '';
    final withoutPath = raw.replaceAll('\\', '/').split('/').last.trim();
    final cleaned = withoutPath
        .replaceAll(_unsafeFileChars, '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\.+'), '')
        .replaceAll(RegExp(r'\.+$'), '')
        .trim();

    if (cleaned.isEmpty) {
      return fallback;
    }

    return cleaned.length > 160 ? cleaned.substring(0, 160) : cleaned;
  }

  static String sanitizeRelativePath(
    String? value, {
    String fallback = 'file',
  }) {
    final normalized = (value ?? '').replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .where((part) => part != '.' && part != '..')
        .map((part) => sanitizeFileName(part, fallback: fallback))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return sanitizeFileName(fallback, fallback: 'file');
    }

    return parts.join('/');
  }

  static bool isValidIpv4(String value) {
    final parts = value.trim().split('.');

    if (parts.length != 4) {
      return false;
    }

    for (final part in parts) {
      final octet = int.tryParse(part);

      if (octet == null || octet < 0 || octet > 255) {
        return false;
      }

      if (part.length > 1 && part.startsWith('0')) {
        return false;
      }
    }

    return true;
  }
}
