import 'dart:io';

class DownloadPathService {
  Future<String> getDownloadPath() async {
    if (Platform.isWindows) {
      final user = Platform.environment['USERPROFILE'];

      return '$user\\Downloads';
    }

    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download';
    }

    throw UnsupportedError('Platform not supported');
  }
}
