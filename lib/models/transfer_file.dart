class TransferFile {
  final String name;
  final String path;
  final int size;

  // relative path inside selected folder
  final String relativePath;

  TransferFile({
    required this.name,
    required this.path,
    required this.size,
    required this.relativePath,
  });
}
