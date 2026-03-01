import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../cotizacion_models.dart';

final cotizacionesRepositoryProvider = Provider<CotizacionesRepository>((ref) {
  return CotizacionesRepository(ref.watch(dioProvider));
});

class CotizacionesRepository {
  final Dio _dio;

  CotizacionesRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return fallback;
  }

  Future<List<CotizacionModel>> list({String? customerPhone, int take = 80}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.cotizaciones,
        queryParameters: {
          if (customerPhone != null && customerPhone.trim().isNotEmpty)
            'customerPhone': customerPhone.trim(),
          'take': take,
        },
      );

      final data = res.data;
      if (data is Map && data['items'] is List) {
        final rows = (data['items'] as List).whereType<Map>();
        return rows
            .map((row) => CotizacionModel.fromApi(row.cast<String, dynamic>()))
            .toList();
      }

      if (data is List) {
        final rows = data.whereType<Map>();
        return rows
            .map((row) => CotizacionModel.fromApi(row.cast<String, dynamic>()))
            .toList();
      }

      return const [];
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar cotizaciones'),
        e.response?.statusCode,
      );
    }
  }

  Future<CotizacionModel> create(CotizacionModel draft) async {
    try {
      final res = await _dio.post(ApiRoutes.cotizaciones, data: draft.toCreateDto());
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<CotizacionModel> update(String id, CotizacionModel draft) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.cotizacionDetail(id),
        data: draft.toCreateDto(),
      );
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteById(String id) async {
    try {
      await _dio.delete(ApiRoutes.cotizacionDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar la cotización'),
        e.response?.statusCode,
      );
    }
  }
}
