import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/debug/trace_log.dart';
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
  static final _backgroundOptions = Options(extra: {'skipLoader': true});

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
    final shouldUseBytes = kIsWeb || normalizedPath.isEmpty;

    if (shouldUseBytes && !hasBytes) {
      throw ApiException('No se pudo leer el archivo seleccionado');
    }
    if (!shouldUseBytes && normalizedPath.isEmpty) {
      throw ApiException('No se encontro el archivo para subir');
    }

    try {
      final multipartFile = shouldUseBytes
          ? MultipartFile.fromBytes(
              bytes!,
              filename: fileName,
              contentType: defaultContentType,
            )
          : await MultipartFile.fromFile(
              normalizedPath,
              filename: fileName,
              contentType: defaultContentType,
            );

      TraceLog.log(
        'UploadRepository',
        'Uploading "$fileName" kind=$kind via ${shouldUseBytes ? 'bytes' : 'path'} contentType=${defaultContentType.mimeType}',
      );

      final response = await _dio.post(
        ApiRoutes.upload,
        data: FormData.fromMap({'file': multipartFile, 'kind': kind}),
        options: _backgroundOptions.copyWith(
          contentType: Headers.multipartFormDataContentType,
        ),
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          onProgress?.call(sent / total);
        },
      );

      return UploadedMedia.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      TraceLog.log(
        'UploadRepository',
        'Upload failed for "$fileName" status=${error.response?.statusCode} response=${_compact(error.response?.data)}',
        error: error,
        stackTrace: error.stackTrace,
      );

      final data = error.response?.data;
      String message = fallbackMessage;
      if (data is Map) {
        final value = data['message'];
        if (value is String && value.trim().isNotEmpty) {
          message = value.trim();
        } else if (value is List && value.isNotEmpty && value.first is String) {
          message = (value.first as String).trim();
        }
      } else if (data is String && data.trim().isNotEmpty) {
        final parsed = _tryParseJsonMap(data);
        final value = parsed?['message'];
        if (value is String && value.trim().isNotEmpty) {
          message = value.trim();
        } else {
          message = data.trim();
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

  Map<String, dynamic>? _tryParseJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    return null;
  }

  String _compact(dynamic value) {
    if (value == null) return 'null';
    if (value is String) {
      return value.length <= 300 ? value : '${value.substring(0, 300)}...';
    }
    try {
      final text = jsonEncode(value);
      return text.length <= 300 ? text : '${text.substring(0, 300)}...';
    } catch (_) {
      return value.toString();
    }
  }
}
