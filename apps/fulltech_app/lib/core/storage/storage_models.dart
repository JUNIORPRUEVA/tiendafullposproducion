typedef JsonMap = Map<String, dynamic>;

class StoragePresignResponseModel {
  final String uploadUrl;
  final String objectKey;
  final String publicUrl;
  final int expiresIn;
  final String? mediaType;
  final String? mimeType;

  const StoragePresignResponseModel({
    required this.uploadUrl,
    required this.objectKey,
    required this.publicUrl,
    required this.expiresIn,
    this.mediaType,
    this.mimeType,
  });

  factory StoragePresignResponseModel.fromJson(JsonMap json) {
    return StoragePresignResponseModel(
      uploadUrl: (json['uploadUrl'] ?? '').toString(),
      objectKey: (json['objectKey'] ?? '').toString(),
      publicUrl: (json['publicUrl'] ?? '').toString(),
      expiresIn: (json['expiresIn'] is num)
          ? (json['expiresIn'] as num).toInt()
          : int.tryParse((json['expiresIn'] ?? '0').toString()) ?? 0,
      mediaType: json['mediaType']?.toString(),
      mimeType: json['mimeType']?.toString(),
    );
  }
}

class ServiceMediaModel {
  final String id;
  final String serviceId;
  final String fileUrl;
  final String fileType;
  final String? caption;
  final String? storageProvider;
  final String? objectKey;
  final String? originalFileName;
  final String? mimeType;
  final String? mediaType;
  final String? kind;
  final int? fileSize;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String? executionReportId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ServiceMediaModel({
    required this.id,
    required this.serviceId,
    required this.fileUrl,
    required this.fileType,
    this.caption,
    this.storageProvider,
    this.objectKey,
    this.originalFileName,
    this.mimeType,
    this.mediaType,
    this.kind,
    this.fileSize,
    this.width,
    this.height,
    this.durationSeconds,
    this.executionReportId,
    this.createdAt,
    this.updatedAt,
  });

  factory ServiceMediaModel.fromJson(JsonMap json) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return ServiceMediaModel(
      id: (json['id'] ?? '').toString(),
      serviceId: (json['serviceId'] ?? '').toString(),
      fileUrl: (json['fileUrl'] ?? '').toString(),
      fileType: (json['fileType'] ?? '').toString(),
      caption: json['caption']?.toString(),
      storageProvider: json['storageProvider']?.toString(),
      objectKey: json['objectKey']?.toString(),
      originalFileName: json['originalFileName']?.toString(),
      mimeType: json['mimeType']?.toString(),
      mediaType: json['mediaType']?.toString(),
      kind: json['kind']?.toString(),
      fileSize: asInt(json['fileSize']),
      width: asInt(json['width']),
      height: asInt(json['height']),
      durationSeconds: asInt(json['durationSeconds']),
      executionReportId: json['executionReportId']?.toString(),
      createdAt: asDate(json['createdAt']),
      updatedAt: asDate(json['updatedAt']),
    );
  }
}
