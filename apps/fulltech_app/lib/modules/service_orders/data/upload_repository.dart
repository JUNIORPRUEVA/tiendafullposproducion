import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';

typedef UploadProgressCallback = void Function(double progress);

final uploadRepositoryProvider = Provider<UploadRepository>((ref) {
  return UploadRepository(ref.watch(dioProvider));
});

class UploadedMedia {
  final String url;
  final String? objectKey;
  final String fileName;
  final String mediaType;
  final String? contentType;
  final int? size;

  const UploadedMedia({
    required this.url,
    required this.fileName,
    required this.mediaType,
    this.objectKey,
    this.contentType,
    this.size,
  });

  factory UploadedMedia.fromJson(Map<String, dynamic> json) {
    return UploadedMedia(
      url: (json['url'] ?? '').toString(),
      objectKey: json['objectKey']?.toString(),
      fileName: (json['fileName'] ?? '').toString(),
      mediaType: (json['mediaType'] ?? '').toString(),
      contentType: json['contentType']?.toString(),
      size: json['size'] is num ? (json['size'] as num).toInt() : null,
    );
  }
}

class UploadRepository {
  UploadRepository(this._dio);

  final Dio _dio;

  Future<UploadedMedia> uploadImage({
    required String fileName,
    List<int>? bytes,
    String? path,
    UploadProgressCallback? onProgress,
  }) {
    return _upload(
      fileName: fileName,
      bytes: bytes,
      path: path,
      kind: 'service_order_image',
      fallbackMessage: 'No se pudo subir la imagen',
      defaultContentType: _imageContentType(fileName),
      onProgress: onProgress,
    );
  }

  Future<UploadedMedia> uploadVideo({
    required String fileName,
    List<int>? bytes,
    String? path,
    UploadProgressCallback? onProgress,
  }) {
    return _upload(
      fileName: fileName,
      bytes: bytes,
      path: path,
      kind: 'service_order_video',
      fallbackMessage: 'No se pudo subir el video',
      defaultContentType: _videoContentType(fileName),
      onProgress: onProgress,
    );
  }

  Future<UploadedMedia> _upload({
    required String fileName,
    required String kind,
    required String fallbackMessage,
    required MediaType defaultContentType,
    List<int>? bytes,
    String? path,
    UploadProgressCallback? onProgress,
  }) async {
    final normalizedPath = (path ?? '').trim();
    final hasBytes = bytes != null && bytes.isNotEmpty;
    if (normalizedPath.isEmpty && !hasBytes) {
      throw ApiException('No se encontró el archivo para subir');
    }

    try {
      final multipartFile = normalizedPath.isNotEmpty
          ? await MultipartFile.fromFile(
              normalizedPath,
              filename: fileName,
              contentType: defaultContentType,
            )
          : MultipartFile.fromBytes(
              bytes!,
              filename: fileName,
              contentType: defaultContentType,
            );

      final response = await _dio.post(
        ApiRoutes.upload,
        data: FormData.fromMap({
          'file': multipartFile,
          'kind': kind,
        }),
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          onProgress?.call(sent / total);
        },
      );
      return UploadedMedia.fromJson((response.data as Map).cast<String, dynamic>());
    } on DioException catch (error) {
      final data = error.response?.data;
      String message = fallbackMessage;
      if (data is Map) {
        final value = data['message'];
        if (value is String && value.trim().isNotEmpty) {
          message = value;
        } else if (value is List && value.isNotEmpty && value.first is String) {
          message = (value.first as String).trim();
        }
      }
      throw ApiException(message, error.response?.statusCode);
    }
  }

  MediaType _imageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  MediaType _videoContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mov')) return MediaType('video', 'quicktime');
    if (lower.endsWith('.webm')) return MediaType('video', 'webm');
    if (lower.endsWith('.mkv')) return MediaType('video', 'x-matroska');
    return MediaType('video', 'mp4');
  }
}