import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../../core/utils/file_utils.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(dioProvider));
});

class CatalogRepository {
  final Dio _dio;
  CatalogRepository(this._dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      const keys = ['items', 'data', 'products', 'rows'];
      for (final key in keys) {
        final candidate = data[key];
        if (candidate is List) return candidate;
      }
    }
    return const [];
  }

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

  Future<List<ProductModel>> fetchProducts() async {
    try {
      final res = await _dio.get(ApiRoutes.products);
      final rows = _extractRows(res.data);
      return rows
          .whereType<Map>()
          .map((row) => ProductModel.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los productos',
        ),
        e.response?.statusCode,
      );
    } catch (_) {
      throw ApiException('No se pudieron cargar los productos');
    }
  }

  Future<String> uploadImage({
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: detectImageMime(filename),
        ),
      });
      final res = await _dio.post(ApiRoutes.productsUpload, data: formData);
      final data = res.data;
      if (data is Map && data['url'] is String) {
        return data['url'] as String;
      }
      if (data is Map && data['path'] is String) {
        return data['path'] as String;
      }
      throw ApiException('No se recibió la ruta de la imagen');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir la imagen'),
        e.response?.statusCode,
      );
    }
  }

  Future<ProductModel> createProduct({
    required String nombre,
    required double precio,
    required double costo,
    required String fotoUrl,
    required String categoria,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.products,
        data: {
          'nombre': nombre,
          'precio': precio,
          'costo': costo,
          'fotoUrl': fotoUrl,
          'categoria': categoria,
        },
      );
      return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el producto'),
        e.response?.statusCode,
      );
    }
  }

  Future<ProductModel> updateProduct({
    required String id,
    required String nombre,
    required double precio,
    required double costo,
    String? fotoUrl,
    String? categoria,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.updateProduct(id),
        data: {
          'nombre': nombre,
          'precio': precio,
          'costo': costo,
          'fotoUrl': fotoUrl,
          'categoria': categoria,
        },
      );
      return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el producto'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _dio.delete(ApiRoutes.deleteProduct(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el producto'),
        e.response?.statusCode,
      );
    }
  }
}
