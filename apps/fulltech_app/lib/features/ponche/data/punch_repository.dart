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
  static const int _scheduledStartMinutes = 9 * 60;
  static const int _scheduledEndMinutes = 18 * 60;
  static const int _lunchExpectedMinutes = 60;
  static const int _permisoExpectedMinutes = 60;
  static const int _workdayMinutes = 8 * 60;
  static const Set<int> _weekendDays = {0};

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

  DateTime _toDominicanLocal(DateTime date) {
    final utc = date.toUtc();
    return utc.subtract(const Duration(hours: 4));
  }

  String _dominicanDayKey(DateTime date) {
    final local = _toDominicanLocal(date);
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _minutesSinceMidnightRd(DateTime date) {
    final local = _toDominicanLocal(date);
    return local.hour * 60 + local.minute;
  }

  int _diffMinutes(DateTime end, DateTime start) {
    return ((end.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / 60000)
        .round();
  }

  bool _isWeekend(String dateKey) {
    final localMidnight = DateTime.tryParse('${dateKey}T00:00:00') ?? DateTime.now();
    return _weekendDays.contains(localMidnight.weekday % 7);
  }

  PunchModel? _firstPunchOfType(List<PunchModel> punches, PunchType type) {
    for (final punch in punches) {
      if (punch.type == type) return punch;
    }
    return null;
  }

  PunchModel? _lastPunchOfType(List<PunchModel> punches, PunchType type) {
    for (var index = punches.length - 1; index >= 0; index--) {
      final punch = punches[index];
      if (punch.type == type) return punch;
    }
    return null;
  }

  ({PunchModel? start, PunchModel? end}) _pairPunches(
    List<PunchModel> punches,
    PunchType startType,
    PunchType endType,
  ) {
    final start = _firstPunchOfType(punches, startType);
    if (start == null) return (start: null, end: null);
    for (final punch in punches) {
      if (punch.type == endType && punch.timestamp.isAfter(start.timestamp)) {
        return (start: start, end: punch);
      }
    }
    return (start: start, end: null);
  }

  ({int minutes, bool complete}) _durationMinutes(
    ({PunchModel? start, PunchModel? end}) pair,
    int fallback,
  ) {
    if (pair.start != null && pair.end != null) {
      return (
        minutes: _diffMinutes(pair.end!.timestamp, pair.start!.timestamp).clamp(0, 1 << 30),
        complete: true,
      );
    }
    if (pair.start != null || pair.end != null) {
      return (minutes: fallback, complete: false);
    }
    return (minutes: 0, complete: true);
  }

  AttendanceDayMetrics _computeDayMetrics(String dateKey, List<PunchModel> punches) {
    final sorted = [...punches]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final entry = _firstPunchOfType(sorted, PunchType.entradaLabor);
    final exit = _lastPunchOfType(sorted, PunchType.salidaLabor);
    final isWeekend = _isWeekend(dateKey);
    final lunch = _durationMinutes(
      _pairPunches(sorted, PunchType.salidaAlmuerzo, PunchType.entradaAlmuerzo),
      _lunchExpectedMinutes,
    );
    final permiso = _durationMinutes(
      _pairPunches(sorted, PunchType.salidaPermiso, PunchType.entradaPermiso),
      _permisoExpectedMinutes,
    );

    final tardinessMinutes = entry != null && !isWeekend
        ? (_minutesSinceMidnightRd(entry.timestamp) - _scheduledStartMinutes)
            .clamp(0, 1 << 30)
        : 0;
    final earlyLeaveMinutes = exit != null && !isWeekend
        ? (_scheduledEndMinutes - _minutesSinceMidnightRd(exit.timestamp))
            .clamp(0, 1 << 30)
        : 0;
    final workedMinutesNet = entry != null && exit != null
        ? (_diffMinutes(exit.timestamp, entry.timestamp) - lunch.minutes - permiso.minutes)
            .clamp(0, 1 << 30)
        : null;
    final incomplete = entry == null || exit == null;
    final unfavorableMinutes = isWeekend
        ? 0
        : incomplete || workedMinutesNet == null
        ? _workdayMinutes
        : (_workdayMinutes - workedMinutesNet).clamp(0, 1 << 30);
    final favorableMinutes = workedMinutesNet == null || workedMinutesNet <= 0
        ? 0
        : isWeekend
        ? workedMinutesNet
        : (workedMinutesNet - _workdayMinutes).clamp(0, 1 << 30);
    final incidents = <AttendanceIncident>[];
    if (!isWeekend && tardinessMinutes > 0) {
      incidents.add(
        AttendanceIncident(
          type: 'TARDY',
          minutes: tardinessMinutes,
          referenceTime: entry?.timestamp,
        ),
      );
    }
    if (!isWeekend && earlyLeaveMinutes > 0) {
      incidents.add(
        AttendanceIncident(
          type: 'EARLY',
          minutes: earlyLeaveMinutes,
          referenceTime: exit?.timestamp,
        ),
      );
    }
    if (!isWeekend && incomplete) {
      incidents.add(
        AttendanceIncident(
          type: 'INCOMPLETE',
          minutes: _workdayMinutes,
          referenceTime: entry?.timestamp ?? exit?.timestamp,
        ),
      );
    }

    return AttendanceDayMetrics(
      date: dateKey,
      entry: entry?.timestamp,
      exit: exit?.timestamp,
      expectedWorkMinutes: isWeekend ? 0 : _workdayMinutes,
      lunchMinutes: lunch.minutes,
      lunchComplete: lunch.complete,
      permisoMinutes: permiso.minutes,
      permisoComplete: permiso.complete,
      tardinessMinutes: tardinessMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes,
      workedMinutesNet: workedMinutesNet,
      favorableMinutes: favorableMinutes,
      unfavorableMinutes: unfavorableMinutes,
      balanceMinutes: favorableMinutes - unfavorableMinutes,
      notWorkedMinutes: unfavorableMinutes,
      incomplete: incomplete,
      isWeekend: isWeekend,
      incidents: incidents,
    );
  }

  AttendanceAggregateMetrics _aggregateDays(List<AttendanceDayMetrics> days) {
    var tardinessMinutes = 0;
    var earlyLeaveMinutes = 0;
    var notWorkedMinutes = 0;
    var workedMinutes = 0;
    var favorableMinutes = 0;
    var unfavorableMinutes = 0;
    var balanceMinutes = 0;
    var incompleteDays = 0;
    var incidentsCount = 0;

    for (final day in days) {
      tardinessMinutes += day.tardinessMinutes;
      earlyLeaveMinutes += day.earlyLeaveMinutes;
      notWorkedMinutes += day.notWorkedMinutes;
      workedMinutes += day.workedMinutesNet ?? 0;
      favorableMinutes += day.favorableMinutes;
      unfavorableMinutes += day.unfavorableMinutes;
      balanceMinutes += day.balanceMinutes;
      if (day.incomplete) incompleteDays += 1;
      incidentsCount += day.incidents.length;
    }

    return AttendanceAggregateMetrics(
      tardinessMinutes: tardinessMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes,
      notWorkedMinutes: notWorkedMinutes,
      workedMinutes: workedMinutes,
      favorableMinutes: favorableMinutes,
      unfavorableMinutes: unfavorableMinutes,
      balanceMinutes: balanceMinutes,
      incompleteDays: incompleteDays,
      incidentsCount: incidentsCount,
    );
  }

  AttendanceDetailModel _buildAttendanceDetailFromPunches(List<PunchModel> punches) {
    final grouped = <String, List<PunchModel>>{};
    for (final punch in punches) {
      final key = _dominicanDayKey(punch.timestamp);
      grouped.putIfAbsent(key, () => <PunchModel>[]).add(punch);
    }

    final days = grouped.entries
        .map((entry) => _computeDayMetrics(entry.key, entry.value))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final firstUser = punches.isNotEmpty ? punches.first.user : null;

    return AttendanceDetailModel(
      user: AttendanceUser(
        id: firstUser?.id ?? '',
        email: firstUser?.email ?? '',
        nombreCompleto: firstUser?.nombreCompleto ?? 'Mi asistencia',
        role: firstUser?.role ?? 'ASISTENTE',
      ),
      punches: punches,
      days: days,
      totals: _aggregateDays(days),
    );
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

  Future<AttendanceDetailModel> fetchMyAttendanceDetail({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.punchMeAttendance,
        queryParameters: _queryParams(from: from, to: to),
      );
      final data = res.data;
      if (data is Map) {
        return AttendanceDetailModel.fromJson(data.cast<String, dynamic>());
      }
      throw ApiException('Respuesta inválida del detalle de asistencia');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        final punches = await listMine(from: from, to: to);
        return _buildAttendanceDetailFromPunches(punches);
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar tu balance de horas'),
        e.response?.statusCode,
      );
    }
  }
}
