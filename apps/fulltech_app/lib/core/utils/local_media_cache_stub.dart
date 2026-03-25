Future<String?> saveLocalMediaCopy({
  required String module,
  required String scopeId,
  required String fileName,
  List<int>? bytes,
  String? sourcePath,
}) async {
  final normalizedPath = (sourcePath ?? '').trim();
  return normalizedPath.isEmpty ? null : normalizedPath;
}
