import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_mapper.dart';
import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../models/publicidad_image_model.dart';

final publicidadImagesRepositoryProvider =
    Provider<PublicidadImagesRepository>((ref) {
  return PublicidadImagesRepository(ref.watch(dioProvider));
});

class PublicidadImagesRepository {
  final Dio _dio;

  PublicidadImagesRepository(this._dio);

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  Future<PublicidadImage> create({
    required String url,
    String? caption,
  }) async {
    try {
      final response = await _dio.post(
        ApiRoutes.publicidadImages,
        data: {
          'url': url,
          if (caption != null && caption.isNotEmpty) 'caption': caption,
        },
      );
      return PublicidadImage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo agregar la imagen');
    }
  }

  Future<List<PublicidadImage>> getAll() async {
    try {
      final response = await _dio.get(ApiRoutes.publicidadImages);
      final List<dynamic> items =
          (response.data is List ? response.data : response.data['items'] ?? []) as List;
      return items
          .map((e) => PublicidadImage.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo cargar las imágenes de publicidad');
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete('${ApiRoutes.publicidadImages}/$id');
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo eliminar la imagen');
    }
  }

  Future<PublicidadImage> update(String id, {String? caption}) async {
    try {
      final response = await _dio.patch(
        '${ApiRoutes.publicidadImages}/$id',
        data: {
          if (caption != null) 'caption': caption,
        },
      );
      return PublicidadImage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo actualizar la imagen');
    }
  }

  Future<UploadUrlResponse> generateUploadUrl(String filename) async {
    try {
      final response = await _dio.post(
        '${ApiRoutes.publicidadImages}/upload-url',
        data: {'filename': filename},
      );
      return UploadUrlResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _rethrow(e, 'No se pudo obtener la URL de subida');
    }
  }

  /// Upload bytes directly to presigned URL (S3/R2).
  /// Uses a dedicated Dio instance so auth interceptors don't interfere.
  Future<void> uploadBytes(
    String presignedUrl,
    Uint8List bytes,
    String contentType,
  ) async {
    // Dedicated Dio — no auth headers, direct PUT to R2
    final uploadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 3),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    try {
      final response = await uploadDio.put(
        presignedUrl,
        data: bytes, // Dio accepts Uint8List directly
        options: Options(
          contentType: contentType,
          headers: {
            'Content-Type': contentType,
            'Content-Length': bytes.length,
          },
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      if ((response.statusCode ?? 0) >= 400) {
        throw Exception(
          'Error subiendo al almacenamiento: ${response.statusCode}',
        );
      }
    } finally {
      uploadDio.close();
    }
  }
}

class UploadUrlResponse {
  final String uploadUrl;
  final String objectKey;
  final String publicUrl;

  UploadUrlResponse({
    required this.uploadUrl,
    required this.objectKey,
    required this.publicUrl,
  });

  factory UploadUrlResponse.fromJson(Map<String, dynamic> json) {
    return UploadUrlResponse(
      uploadUrl: json['uploadUrl'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      publicUrl: json['publicUrl'] as String? ?? '',
    );
  }
}
