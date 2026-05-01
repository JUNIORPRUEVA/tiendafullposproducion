import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import 'employee_warning_model.dart';

final employeeWarningsRepositoryProvider =
    Provider<EmployeeWarningsRepository>((ref) {
  return EmployeeWarningsRepository(ref.watch(dioProvider));
});

class EmployeeWarningsRepository {
  final Dio _dio;

  EmployeeWarningsRepository(this._dio);

  // ── Admin ──────────────────────────────────────────────────────────────────

  Future<EmployeeWarningsPage> listAll({
    String? employeeUserId,
    String? status,
    String? severity,
    String? category,
    String? search,
    String? fromDate,
    String? toDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _dio.get(
      ApiRoutes.employeeWarnings,
      queryParameters: {
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (status != null) 'status': status,
        if (severity != null) 'severity': severity,
        if (category != null) 'category': category,
        if (search != null && search.isNotEmpty) 'search': search,
        if (fromDate != null) 'fromDate': fromDate,
        if (toDate != null) 'toDate': toDate,
        'page': page,
        'limit': limit,
      },
    );
    return EmployeeWarningsPage.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> getOne(String id) async {
    final res = await _dio.get(ApiRoutes.employeeWarningDetail(id));
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> create(Map<String, dynamic> data) async {
    final res = await _dio.post(ApiRoutes.employeeWarnings, data: data);
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.put(ApiRoutes.employeeWarningUpdate(id), data: data);
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete(ApiRoutes.employeeWarningDelete(id));
  }

  Future<EmployeeWarning> submit(String id) async {
    final res = await _dio.post(ApiRoutes.employeeWarningSubmit(id));
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> annul(String id, String reason) async {
    final res = await _dio.post(
      ApiRoutes.employeeWarningAnnul(id),
      data: {'annulmentReason': reason},
    );
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String> generatePdf(String id) async {
    final res = await _dio.post(ApiRoutes.employeeWarningPdf(id));
    return (res.data as Map<String, dynamic>)['pdfUrl'] as String;
  }

  Future<void> uploadEvidence(String id, FormData formData) async {
    await _dio.post(
      ApiRoutes.employeeWarningEvidences(id),
      data: formData,
    );
  }

  // ── Employee ───────────────────────────────────────────────────────────────

  Future<List<EmployeeWarning>> myPending() async {
    final res = await _dio.get(ApiRoutes.employeeWarningsMyPending);
    final list = res.data as List<dynamic>;
    return list
        .map((e) => EmployeeWarning.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmployeeWarning> myWarning(String id) async {
    final res = await _dio.get(ApiRoutes.employeeWarningsMy(id));
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  /// Downloads the warning PDF bytes through the authenticated API endpoint.
  /// Returns the raw bytes to be rendered with SfPdfViewer.memory().
  Future<Uint8List> getMyWarningPdfBytes(String id) async {
    final res = await _dio.get<List<int>>(
      ApiRoutes.employeeWarningsMyPdf(id),
      options: Options(responseType: ResponseType.bytes),
    );
    if (res.data == null || res.data!.isEmpty) {
      throw Exception('El servidor no devolvió contenido del PDF');
    }
    return Uint8List.fromList(res.data!);
  }

  Future<EmployeeWarning> sign(
    String id, {
    required String typedName,
    String? comment,
    String? deviceInfo,
  }) async {
    final res = await _dio.post(
      ApiRoutes.employeeWarningsMySign(id),
      data: {
        'typedName': typedName,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        if (deviceInfo != null) 'deviceInfo': deviceInfo,
      },
    );
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> refuse(
    String id, {
    required String typedName,
    required String comment,
    String? deviceInfo,
  }) async {
    final res = await _dio.post(
      ApiRoutes.employeeWarningsMyRefuse(id),
      data: {
        'typedName': typedName,
        'comment': comment,
        if (deviceInfo != null) 'deviceInfo': deviceInfo,
      },
    );
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }
}
