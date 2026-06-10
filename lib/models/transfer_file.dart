class TransferFile {
  final String name;
  final String path;
  final int size;

  // relative path inside selected folder
  final String relativePath;
  final String? contentUri;
  final bool isFolder;

  const TransferFile({
    required this.name,
    required this.path,
    required this.size,
    required this.relativePath,
    this.contentUri,
    this.isFolder = false,
  });

  const TransferFile.folder({
    required this.name,
    required this.path,
    required this.relativePath,
    this.contentUri,
  }) : size = 0,
       isFolder = true;

  bool get usesContentUri => contentUri != null && contentUri!.isNotEmpty;
}
