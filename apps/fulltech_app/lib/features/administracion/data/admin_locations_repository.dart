import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../models/admin_locations_models.dart';

final adminLocationsRepositoryProvider = Provider<AdminLocationsRepository>((
  ref,
) {
  return AdminLocationsRepository(ref.watch(dioProvider));
});

class AdminLocationsRepository {
  final Dio _dio;

  AdminLocationsRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    return fallback;
  }

  Future<List<AdminUserLocation>> latest() async {
    try {
      final res = await _dio.get(ApiRoutes.adminLocationsLatest);
      final data = res.data;
      if (data is List) {
        return data
            .whereType<Map>()
            .map(
              (row) => AdminUserLocation.fromJson(row.cast<String, dynamic>()),
            )
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      final fallback = 'No se pudieron cargar ubicaciones';
      throw ApiException(
        _extractMessage(e.response?.data, fallback),
        e.response?.statusCode,
      );
    }
  }
}
