import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart' show dioProvider;
import '../../../core/errors/api_exception.dart';
import '../horarios_models.dart';

final workSchedulingRepositoryProvider = Provider<WorkSchedulingRepository>((
  ref,
) {
  return WorkSchedulingRepository(dio: ref.watch(dioProvider));
});

class WorkSchedulingRepository {
  final Dio _dio;

  WorkSchedulingRepository({required Dio dio}) : _dio = dio;

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    return fallback;
  }

  Future<List<WorkEmployee>> listEmployees() async {
    try {
      final res = await _dio.get(ApiRoutes.workSchedulingEmployees);
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => WorkEmployee.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar empleados de horarios',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<void> updateEmployeeConfig(
    String userId, {
    bool? enabled,
    String? scheduleProfileId,
    int? preferredDayOffWeekday,
    int? fixedDayOffWeekday,
    List<int>? disallowedDayOffWeekdays,
    List<int>? unavailableWeekdays,
    String? notes,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.workSchedulingEmployee(userId),
        data: {
          if (enabled != null) 'enabled': enabled,
          if (scheduleProfileId != null)
            'schedule_profile_id': scheduleProfileId,
          if (preferredDayOffWeekday != null)
            'preferred_day_off_weekday': preferredDayOffWeekday,
          if (fixedDayOffWeekday != null)
            'fixed_day_off_weekday': fixedDayOffWeekday,
          if (disallowedDayOffWeekdays != null)
            'disallowed_day_off_weekdays': disallowedDayOffWeekdays,
          if (unavailableWeekdays != null)
            'unavailable_weekdays': unavailableWeekdays,
          if (notes != null) 'notes': notes,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar configuración'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<WorkScheduleProfile>> listProfiles() async {
    try {
      final res = await _dio.get(ApiRoutes.workSchedulingProfiles);
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => WorkScheduleProfile.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar perfiles'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> upsertProfile({
    String? id,
    required String name,
    required bool isDefault,
    required List<WorkScheduleProfileDay> days,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.workSchedulingProfilesUpsert,
        data: {
          if (id != null && id.trim().isNotEmpty) 'id': id,
          'name': name,
          'is_default': isDefault,
          'days': days.map((d) => d.toUpsertJson()).toList(),
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el perfil'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<WorkCoverageRule>> listCoverageRules() async {
    try {
      final res = await _dio.get(ApiRoutes.workSchedulingCoverageRules);
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => WorkCoverageRule.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar coberturas'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> upsertCoverageRules(List<WorkCoverageRule> rules) async {
    try {
      await _dio.post(
        ApiRoutes.workSchedulingCoverageRulesUpsert,
        data: {
          'rules': rules.map((r) => r.toUpsertJson()).toList(),
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar cobertura'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<WorkScheduleException>> listExceptions({
    String? weekStartDate,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.workSchedulingExceptions,
        queryParameters: {
          if (weekStartDate != null && weekStartDate.trim().isNotEmpty)
            'week_start_date': weekStartDate,
        },
      );
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => WorkScheduleException.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar excepciones'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> createException({
    String? userId,
    required String type,
    required String dateFrom,
    required String dateTo,
    String? note,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.workSchedulingExceptions,
        data: {
          if (userId != null && userId.trim().isNotEmpty) 'user_id': userId,
          'type': type,
          'date_from': dateFrom,
          'date_to': dateTo,
          if (note != null) 'note': note,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear excepción'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> updateException({
    required String id,
    required String type,
    required String dateFrom,
    required String dateTo,
    String? note,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.workSchedulingException(id),
        data: {
          'type': type,
          'date_from': dateFrom,
          'date_to': dateTo,
          if (note != null) 'note': note,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar excepción'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteException(String id) async {
    try {
      await _dio.post(ApiRoutes.workSchedulingExceptionDelete(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar excepción'),
        e.response?.statusCode,
      );
    }
  }

  Future<WorkWeekSchedule?> getWeek(String weekStartDate) async {
    try {
      final res = await _dio.get(ApiRoutes.workSchedulingWeek(weekStartDate));
      final data = res.data;
      if (data == null) return null;
      if (data is Map) {
        return WorkWeekSchedule.fromJson(data.cast<String, dynamic>());
      }
      return null;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar la semana'),
        e.response?.statusCode,
      );
    }
  }

  Future<WorkWeekSchedule> generateWeek({
    required String weekStartDate,
    String mode = 'REPLACE',
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.workSchedulingWeeksGenerate,
        data: {
          'week_start_date': weekStartDate,
          'mode': mode,
          if (note != null && note.trim().isNotEmpty) 'note': note,
        },
      );
      return WorkWeekSchedule.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo generar la semana'),
        e.response?.statusCode,
      );
    }
  }

  Future<WorkWeekSchedule> manualMoveDayOff({
    required String weekStartDate,
    required String userId,
    required String fromDate,
    required String toDate,
    required String reason,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.workSchedulingManualMoveDayOff,
        data: {
          'week_start_date': weekStartDate,
          'user_id': userId,
          'from_date': fromDate,
          'to_date': toDate,
          'reason': reason,
        },
      );
      return WorkWeekSchedule.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo mover el día libre'),
        e.response?.statusCode,
      );
    }
  }

  Future<WorkWeekSchedule> manualSwapDayOff({
    required String weekStartDate,
    required String userAId,
    required String userADayOffDate,
    required String userBId,
    required String userBDayOffDate,
    required String reason,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.workSchedulingManualSwapDayOff,
        data: {
          'week_start_date': weekStartDate,
          'user_a_id': userAId,
          'user_a_day_off_date': userADayOffDate,
          'user_b_id': userBId,
          'user_b_day_off_date': userBDayOffDate,
          'reason': reason,
        },
      );
      return WorkWeekSchedule.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo intercambiar el día libre',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<WorkScheduleAuditLog>> listAudit({
    String? targetUserId,
    String? from,
    String? to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.workSchedulingAudit,
        queryParameters: {
          if (targetUserId != null && targetUserId.trim().isNotEmpty)
            'target_user_id': targetUserId,
          if (from != null && from.trim().isNotEmpty) 'from': from,
          if (to != null && to.trim().isNotEmpty) 'to': to,
        },
      );
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => WorkScheduleAuditLog.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar auditoría'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> reportMostChanges({
    required String from,
    required String to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.workSchedulingReportMostChanges,
        queryParameters: {'from': from, 'to': to},
      );
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar reporte'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> reportLowCoverage({
    required String from,
    required String to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.workSchedulingReportLowCoverage,
        queryParameters: {'from': from, 'to': to},
      );
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar reporte'),
        e.response?.statusCode,
      );
    }
  }
}
