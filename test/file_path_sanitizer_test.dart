import 'package:flutter_test/flutter_test.dart';
import 'package:lan_share/services/file_path_sanitizer.dart';

void main() {
  test('sanitizes unsafe file names', () {
    expect(
      FilePathSanitizer.sanitizeFileName('../bad:name?.txt'),
      'bad_name_.txt',
    );
  });

  test('removes parent-directory path segments', () {
    expect(
      FilePathSanitizer.sanitizeRelativePath('photos/../../safe/image.png'),
      'photos/safe/image.png',
    );
  });

  test('validates IPv4 addresses', () {
    expect(FilePathSanitizer.isValidIpv4('192.168.1.20'), isTrue);
    expect(FilePathSanitizer.isValidIpv4('999.168.1.20'), isFalse);
    expect(FilePathSanitizer.isValidIpv4('192.168.01.20'), isFalse);
  });
}
