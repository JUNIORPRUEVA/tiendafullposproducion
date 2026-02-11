import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/punch_model.dart';
import '../models/attendance_models.dart';

final punchRepositoryProvider = Provider<PunchRepository>((ref) {
  return PunchRepository(ref.watch(dioProvider));
});

class PunchRepository {
  final Dio _dio;

  PunchRepository(this._dio);

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

  Map<String, dynamic> _queryParams({DateTime? from, DateTime? to, String? userId, bool incidentsOnly = false}) {
    final params = <String, dynamic>{};
    if (from != null) params['from'] = from.toIso8601String();
    if (to != null) params['to'] = to.toIso8601String();
    if (userId != null && userId.trim().isNotEmpty) params['userId'] = userId.trim();
    if (incidentsOnly) params['incidentsOnly'] = true;
    return params;
  }

  Future<PunchModel> createPunch(PunchType type) async {
    try {
      final res = await _dio.post(ApiRoutes.punch, data: {'type': type.apiValue});
      return PunchModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo registrar el ponche'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PunchModel>> listMine({DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get(ApiRoutes.punchMe, queryParameters: _queryParams(from: from, to: to));
      final data = res.data;
      if (data is List) {
        return data.map((e) => PunchModel.fromJson((e as Map).cast<String, dynamic>())).toList();
      }
      return [];
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo obtener el historial'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PunchModel>> listAdmin({String? userId, DateTime? from, DateTime? to}) async {
    try {
      final res = await _dio.get(ApiRoutes.punchAdmin, queryParameters: _queryParams(from: from, to: to, userId: userId));
      final data = res.data;
      if (data is List) {
        return data.map((e) => PunchModel.fromJson((e as Map).cast<String, dynamic>())).toList();
      }
      return [];
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo obtener los ponches'),
        e.response?.statusCode,
      );
    }
  }

  Future<AttendanceSummaryModel> fetchAttendanceSummary({
    DateTime? from,
    DateTime? to,
    String? userId,
    bool incidentsOnly = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.punchAttendanceSummary,
        queryParameters: _queryParams(
          from: from,
          to: to,
          userId: userId,
          incidentsOnly: incidentsOnly,
        ),
      );
      final data = res.data;
      if (data is Map) {
        return AttendanceSummaryModel.fromJson(data.cast<String, dynamic>());
      }
      throw ApiException('Respuesta inválida del resumen de asistencia');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el resumen de asistencia'),
        e.response?.statusCode,
      );
    }
  }

  Future<AttendanceDetailModel> fetchAttendanceDetail(
    String userId, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.punchAttendanceUser(userId),
        queryParameters: _queryParams(from: from, to: to),
      );
      final data = res.data;
      if (data is Map) {
        return AttendanceDetailModel.fromJson(data.cast<String, dynamic>());
      }
      throw ApiException('Respuesta inválida del detalle de asistencia');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el detalle del usuario'),
        e.response?.statusCode,
      );
    }
  }
}
