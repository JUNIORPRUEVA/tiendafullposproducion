enum PendingEvidenceStatus {
  uploading,
  failed,
}

class PendingEvidenceUpload {
  final String id;
  final String fileName;
  final String mimeType;
  final String caption;
  final int fileSize;
  final String? path;
  final List<int>? bytes;
  final double progress;
  final PendingEvidenceStatus status;

  const PendingEvidenceUpload({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.caption,
    required this.fileSize,
    this.path,
    this.bytes,
    this.progress = 0,
    this.status = PendingEvidenceStatus.uploading,
  });

  bool get isImage => mimeType.trim().toLowerCase().startsWith('image/');
  bool get isVideo => mimeType.trim().toLowerCase().startsWith('video/');

  PendingEvidenceUpload copyWith({
    double? progress,
    PendingEvidenceStatus? status,
  }) {
    return PendingEvidenceUpload(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      caption: caption,
      fileSize: fileSize,
      path: path,
      bytes: bytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
    );
  }
}
