import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../nomina_models.dart';

final nominaRepositoryProvider = Provider<NominaRepository>((ref) {
  return NominaRepository(ref, ref.watch(dioProvider));
});

class NominaRepository {
  NominaRepository(this.ref, this._dio);

  static const String _companyPayrollScope = 'cloud_company_payroll';

  final Ref ref;
  final Dio _dio;

  String get _currentUserId =>
      (ref.read(authStateProvider).user?.id ?? '').trim();

  String get _ownerId => _companyPayrollScope;

  Future<List<PayrollPeriod>> listPeriods() async {
    final rows = await _getList(ApiRoutes.payrollPeriods);
    return rows.map(PayrollPeriod.fromMap).toList();
  }

  Future<PayrollPeriod?> getPeriodById(String periodId) async {
    final data = await _getMapOrNull(ApiRoutes.payrollPeriodDetail(periodId));
    if (data == null) return null;
    return PayrollPeriod.fromMap(data);
  }

  Future<bool> hasOverlappingOpenPeriod(DateTime start, DateTime end) async {
    final res = await _getMap(ApiRoutes.payrollPeriodOpenOverlap, query: {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
    });
    return res['overlaps'] == true;
  }

  Future<PayrollPeriod> createPeriod(
    DateTime start,
    DateTime end,
    String title,
  ) async {
    final data = await _postMap(ApiRoutes.payrollPeriods, {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'title': title,
    });
    return PayrollPeriod.fromMap(data);
  }

  Future<PayrollPeriod> ensureCurrentOpenPeriod() async {
    final data = await _postMap(ApiRoutes.payrollPeriodEnsureCurrentOpen, const {});
    return PayrollPeriod.fromMap(data);
  }

  Future<PayrollPeriod> createNextOpenPeriod(PayrollPeriod closed) async {
    final data = await _postMap(ApiRoutes.payrollPeriodNextOpen(closed.id), const {});
    return PayrollPeriod.fromMap(data);
  }

  Future<void> closePeriod(String periodId) async {
    await _patch(ApiRoutes.payrollPeriodClose(periodId));
  }

  Future<List<PayrollEmployee>> listEmployees({bool activeOnly = true}) async {
    final rows = await _getList(ApiRoutes.payrollEmployees, query: {
      'activeOnly': activeOnly.toString(),
    });
    return rows.map(PayrollEmployee.fromMap).toList();
  }

  Future<PayrollEmployee?> getEmployeeById(String employeeId) async {
    final data = await _getMapOrNull(ApiRoutes.payrollEmployeeDetail(employeeId));
    if (data == null) return null;
    return PayrollEmployee.fromMap(data);
  }

  Future<PayrollEmployee> upsertEmployee(PayrollEmployee employee) async {
    final data = await _postMap(ApiRoutes.payrollEmployeeUpsert, {
      if (employee.id.isNotEmpty) 'id': employee.id,
      'nombre': employee.nombre,
      'telefono': employee.telefono,
      'puesto': employee.puesto,
      'cuotaMinima': employee.cuotaMinima,
      'seguroLeyMonto': employee.seguroLeyMonto,
      'activo': employee.activo,
    });
    return PayrollEmployee.fromMap(data);
  }

  Future<PayrollEmployeeConfig?> getEmployeeConfig(
    String periodId,
    String employeeId,
  ) async {
    final data = await _getMapOrNull(ApiRoutes.payrollConfig, query: {
      'periodId': periodId,
      'employeeId': employeeId,
    });
    if (data == null) return null;
    return PayrollEmployeeConfig.fromMap(data);
  }

  Future<PayrollEmployeeConfig> upsertEmployeeConfig({
    required String periodId,
    required String employeeId,
    required double baseSalary,
    required bool includeCommissions,
    String? notes,
  }) async {
    final data = await _postMap(ApiRoutes.payrollConfigUpsert, {
      'periodId': periodId,
      'employeeId': employeeId,
      'baseSalary': baseSalary,
      'includeCommissions': includeCommissions,
      'notes': notes,
    });
    return PayrollEmployeeConfig.fromMap(data);
  }

  Future<List<PayrollEntry>> listEntries(String periodId, String employeeId) async {
    final rows = await _getList(ApiRoutes.payrollEntries, query: {
      'periodId': periodId,
      'employeeId': employeeId,
    });
    return rows.map(PayrollEntry.fromMap).toList();
  }

  Future<PayrollEntry> addEntry(PayrollEntry entry) async {
    final data = await _postMap(ApiRoutes.payrollEntries, {
      'periodId': entry.periodId,
      'employeeId': entry.employeeId,
      'date': entry.date.toIso8601String(),
      'type': entry.type.dbValue,
      'concept': entry.concept,
      'amount': entry.amount,
      'cantidad': entry.cantidad,
    });
    return PayrollEntry.fromMap(data);
  }

  Future<void> deleteEntry(String entryId) async {
    await _delete(ApiRoutes.payrollEntryDetail(entryId));
  }

  Future<PayrollTotals> computeTotals(String periodId, String employeeId) async {
    final map = await _getMap(ApiRoutes.payrollTotals, query: {
      'periodId': periodId,
      'employeeId': employeeId,
    });

    return PayrollTotals(
      baseSalary: _num(map['baseSalary']),
      commissions: _num(map['commissions']),
      bonuses: _num(map['bonuses']),
      otherAdditions: _num(map['otherAdditions']),
      absences: _num(map['absences']),
      late: _num(map['late']),
      advances: _num(map['advances']),
      otherDeductions: _num(map['otherDeductions']),
      seguroLey: _num(map['seguroLey']),
      additions: _num(map['additions']),
      deductions: _num(map['deductions']),
      total: _num(map['total']),
    );
  }

  Future<double> computePeriodTotalAllEmployees(String periodId) async {
    final map = await _getMap(ApiRoutes.payrollPeriodTotalAll(periodId));
    return _num(map['total']);
  }

  Future<List<PayrollHistoryItem>> listMyPayrollHistory() async {
    if (_currentUserId.isEmpty) return const [];
    final rows = await _getList(ApiRoutes.payrollMyHistory);
    return rows.map(PayrollHistoryItem.fromMap).toList();
  }

  Future<double> getCuotaMinimaForUser({
    required String userId,
    required String userName,
  }) async {
    try {
      final map = await _getMap(ApiRoutes.payrollMyGoal, query: {
        'userId': userId,
        'userName': userName,
      });
      return _num(map['cuota_minima']);
    } on ApiException catch (e) {
      if (e.code == 404) {
        return 0;
      }
      rethrow;
    }
  }

  String get ownerId => _ownerId;

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del servidor');
    } on DioException catch (e) {
      throw ApiException(_extractMessage(e, 'Error consultando nómina'), e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>?> _getMapOrNull(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      if (res.data == null) return null;
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException(_extractMessage(e, 'Error consultando nómina'), e.response?.statusCode);
    }
  }

  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      final data = res.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
    } on DioException catch (e) {
      throw ApiException(_extractMessage(e, 'Error consultando nómina'), e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> _postMap(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post(path, data: body);
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del servidor');
    } on DioException catch (e) {
      throw ApiException(_extractMessage(e, 'No se pudo guardar nómina'), e.response?.statusCode);
    }
  }

  Future<void> _patch(String path) async {
    try {
      await _dio.patch(path);
    } on DioException catch (e) {
      throw ApiException(_extractMessage(e, 'No se pudo actualizar nómina'), e.response?.statusCode);
    }
  }

  Future<void> _delete(String path) async {
    try {
      await _dio.delete(path);
    } on DioException catch (e) {
      throw ApiException(_extractMessage(e, 'No se pudo eliminar movimiento'), e.response?.statusCode);
    }
  }

  String _extractMessage(DioException e, String fallback) {
    final data = e.response?.data;
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

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
