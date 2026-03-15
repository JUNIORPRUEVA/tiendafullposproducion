import 'dart:async';

import 'package:dio/dio.dart';
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

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
    }
    return fallback;
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
    void Function(int sentBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (bytes == null && stream == null) {
      throw ArgumentError('bytes o stream requerido');
    }

    final direct = Dio();
    await direct.put(
      uploadUrl,
      data: stream ?? Stream.value(bytes!),
      options: Options(
        headers: {'Content-Type': contentType},
        responseType: ResponseType.plain,
      ),
      onSendProgress: onProgress,
      cancelToken: cancelToken,
    );
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
    try {
      final res = await _dio.post(
        ApiRoutes.storageConfirm,
        data: {
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
        },
      );

      return ServiceMediaModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo confirmar la subida'),
        e.response?.statusCode,
      );
    }
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
