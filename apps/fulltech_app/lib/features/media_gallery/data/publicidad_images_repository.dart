import 'package:dio/dio.dart';

import '../../../core/api/api_error_mapper.dart';
import '../../../core/api/api_routes.dart';
import '../models/publicidad_image_model.dart';

class PublicidadImagesRepository {
  final Dio _dio;

  PublicidadImagesRepository(this._dio);

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
    } catch (e) {
      throw ApiErrorMapper.mapError(e);
    }
  }

  Future<List<PublicidadImage>> getAll() async {
    try {
      final response = await _dio.get(ApiRoutes.publicidadImages);

      final List<dynamic> items = response.data['items'] ?? response.data ?? [];
      return items
          .map((e) => PublicidadImage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiErrorMapper.mapError(e);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _dio.delete(
        '${ApiRoutes.publicidadImages}/$id',
      );
    } catch (e) {
      throw ApiErrorMapper.mapError(e);
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
    } catch (e) {
      throw ApiErrorMapper.mapError(e);
    }
  }

  Future<UploadUrlResponse> generateUploadUrl(String filename) async {
    try {
      final response = await _dio.post(
        '${ApiRoutes.publicidadImages}/upload-url',
        data: {'filename': filename},
      );

      return UploadUrlResponse.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw ApiErrorMapper.mapError(e);
    }
  }

  /// Upload file to presigned URL (S3/R2)
  Future<void> uploadFile(
    String presignedUrl,
    String filePath,
    String contentType,
  ) async {
    try {
      final file = await _dio.get(
        filePath,
        options: Options(responseType: ResponseType.bytes),
      );

      await _dio.put(
        presignedUrl,
        data: file.data,
        options: Options(
          contentType: contentType,
          headers: {'Content-Type': contentType},
        ),
      );
    } catch (e) {
      throw ApiErrorMapper.mapError(e);
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
