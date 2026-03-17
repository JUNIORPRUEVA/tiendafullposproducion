import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_repository.dart';
import '../errors/api_exception.dart';
import 'storage_models.dart';

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return StorageRepository(ref.watch(dioProvider));
});

class StorageRepository {
  final Dio _dio;

  StorageRepository(this._dio);

  Future<ServiceMediaModel> getById(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.storageItem(id));
      return ServiceMediaModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el archivo'),
        e.response?.statusCode,
      );
    }
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is String) {
      final raw = data.trim();
      if (raw.isEmpty) return fallback;
      try {
        final decoded = jsonDecode(raw);
        return _extractMessage(decoded, raw);
      } catch (_) {
        return raw;
      }
    }
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return _extractMessage(message, message.trim());
      }
      if (message is List && message.isNotEmpty) {
        final parts = message
            .map((item) => _extractMessage(item, '').trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (parts.isNotEmpty) return parts.join('\n');
      }

      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return fallback;
  }

  bool _shouldRetryConfirm({
    required int? statusCode,
    required String message,
  }) {
    if (statusCode != 400) return false;
    final normalized = message.toLowerCase();
    return normalized.contains('filesize no coincide con el objeto subido');
  }

  /// 1) Solicita un URL presignado para subir directo a R2.
  Future<StoragePresignResponseModel> presign({
    required String serviceId,
    String? executionReportId,
    required String fileName,
    required String contentType,
    required int fileSize,
    required String kind,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.storagePresign,
        data: {
          'serviceId': serviceId,
          if (executionReportId != null && executionReportId.isNotEmpty)
            'executionReportId': executionReportId,
          'fileName': fileName,
          'contentType': contentType,
          'kind': kind,
          'fileSize': fileSize,
        },
      );

      return StoragePresignResponseModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo preparar la subida'),
        e.response?.statusCode,
      );
    }
  }

  /// 2) Sube el archivo directo a R2 con HTTP PUT.
  ///
  /// Importante: NO usar el Dio autenticado para el PUT a R2.
  /// Algunos interceptores/headers (Authorization) pueden romper la subida.
  Future<void> uploadToPresignedUrl({
    required String uploadUrl,
    List<int>? bytes,
    Stream<List<int>>? stream,
    required String contentType,
    int? contentLength,
    void Function(int sentBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (bytes == null && stream == null) {
      throw ArgumentError('bytes o stream requerido');
    }

    final direct = Dio();

    // Browsers block setting Content-Length manually; it can cause Dio/XHR
    // to fail with a generic network error.
    final headers = <String, dynamic>{'Content-Type': contentType};
    if (!kIsWeb && contentLength != null && contentLength > 0) {
      headers['Content-Length'] = contentLength;
    }

    try {
      await direct.put(
        uploadUrl,
        data: bytes != null ? Uint8List.fromList(bytes) : stream,
        options: Options(headers: headers, responseType: ResponseType.plain),
        onSendProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      final uri = e.requestOptions.uri;
      final safeUrl = uri.hasQuery
          ? uri.replace(query: '').toString()
          : uri.toString();
      final hint = kIsWeb
          ? '\nWeb: esto suele ser CORS del bucket, Mixed Content (https->http), o headers prohibidos.'
          : '';
      throw ApiException(
        '[UPLOAD] ${e.message ?? 'Error de red al subir archivo'}\nURL: $safeUrl$hint',
      );
    }
  }

  /// 3) Confirma la subida y guarda metadata en Postgres.
  Future<ServiceMediaModel> confirm({
    required String serviceId,
    String? executionReportId,
    required String objectKey,
    required String publicUrl,
    required String fileName,
    required String mimeType,
    required int fileSize,
    required String kind,
    String? caption,
    int? width,
    int? height,
    int? durationSeconds,
  }) async {
    final payload = {
      'serviceId': serviceId,
      'objectKey': objectKey,
      'publicUrl': publicUrl,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
      'kind': kind,
      if (caption != null && caption.trim().isNotEmpty)
        'caption': caption.trim(),
      if (executionReportId != null && executionReportId.isNotEmpty)
        'executionReportId': executionReportId,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationSeconds != null) 'durationSeconds': durationSeconds,
    };

    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];

    ApiException? lastError;

    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      try {
        final res = await _dio.post(ApiRoutes.storageConfirm, data: payload);

        return ServiceMediaModel.fromJson(
          (res.data as Map).cast<String, dynamic>(),
        );
      } on DioException catch (e) {
        final message = _extractMessage(
          e.response?.data,
          'No se pudo confirmar la subida',
        );
        final statusCode = e.response?.statusCode;
        final apiError = ApiException(message, statusCode);
        lastError = apiError;

        if (!_shouldRetryConfirm(statusCode: statusCode, message: message)) {
          throw apiError;
        }
      }
    }

    throw lastError ?? ApiException('No se pudo confirmar la subida');
  }

  /// 4) Lista archivos de un servicio (opcionalmente filtra por kind/mediaType).
  Future<List<ServiceMediaModel>> listByService({
    required String serviceId,
    String? kind,
    String? mediaType,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.storageByService(serviceId),
        queryParameters: {
          if (kind != null && kind.isNotEmpty) 'kind': kind,
          if (mediaType != null && mediaType.isNotEmpty) 'mediaType': mediaType,
        },
      );

      final list = res.data;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => ServiceMediaModel.fromJson(m.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar archivos'),
        e.response?.statusCode,
      );
    }
  }

  /// 5) Elimina archivo (borra en R2 si aplica + soft delete metadata).
  Future<void> delete(String id) async {
    try {
      await _dio.delete(ApiRoutes.storageItem(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el archivo'),
        e.response?.statusCode,
      );
    }
  }
}
