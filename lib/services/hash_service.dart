import 'dart:io';
import 'package:crypto/crypto.dart';

class HashService {
  static Future<String> calculateSha256(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;

    return digest.toString();
  }
}
