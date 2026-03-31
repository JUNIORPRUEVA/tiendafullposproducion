import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error_mapper.dart';
import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../service_order_models.dart';

final serviceOrdersApiProvider = Provider<ServiceOrdersApi>((ref) {
  return ServiceOrdersApi(ref.watch(dioProvider));
});

class ServiceOrdersApi {
  final Dio _dio;
  static final _backgroundOptions = Options(extra: {'skipLoader': true});

  ServiceOrdersApi(this._dio);

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  void _logRequest(String method, String path) {
    if (!kDebugMode) return;
    final tokenHeader = _dio.options.headers['Authorization'];
    final tokenState = tokenHeader == null
        ? 'missing'
        : tokenHeader.toString().trim().isEmpty
        ? 'empty'
        : 'present';
    debugPrint(
      'SERVICE_ORDERS REQUEST: $method ${_dio.options.baseUrl}$path token=$tokenState',
    );
  }

  void _logResponse(String method, String path, int? statusCode) {
    if (!kDebugMode) return;
    debugPrint(
      'SERVICE_ORDERS RESPONSE: $method ${_dio.options.baseUrl}$path status=${statusCode ?? 'unknown'}',
    );
  }

  void _logError(String method, String path, Object error) {
    if (!kDebugMode) return;
    debugPrint(
      'SERVICE_ORDERS ERROR: $method ${_dio.options.baseUrl}$path error=$error',
    );
  }

  Future<List<ServiceOrderModel>> listOrders() async {
    const path = ApiRoutes.serviceOrders;
    _logRequest('GET', path);
    try {
      final res = await _dio.get(path, options: _backgroundOptions);
      _logResponse('GET', path, res.statusCode);
      final raw = res.data;
      final rows = raw is List
          ? raw
          : raw is Map && raw['items'] is List
          ? raw['items'] as List<dynamic>
          : const <dynamic>[];
      return rows
          .whereType<Map>()
          .map((row) => ServiceOrderModel.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (error) {
      _logError('GET', path, error);
      _rethrow(error, 'No se pudieron cargar las órdenes');
    } catch (error) {
      _logError('GET', path, error);
      throw ApiException.detailed(
        message:
            'No se pudieron cargar las órdenes. El servidor respondió con un formato inválido.',
        type: ApiErrorType.parse,
        displayCode: 'PARSE_ERROR',
        technicalDetails: error.toString(),
        retryable: false,
      );
    }
  }

  Future<ServiceOrderModel> getOrder(String id) async {
    try {
      final res = await _dio.get(
        ApiRoutes.serviceOrderDetail(id),
        options: _backgroundOptions,
      );
      return ServiceOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la orden');
    }
  }

  Future<ServiceOrderModel> createOrder(
    CreateServiceOrderRequest request,
  ) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceOrders,
        data: request.toJson(),
        options: _backgroundOptions,
      );
      return ServiceOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo crear la orden');
    }
  }

  Future<ServiceOrderModel> updateOrder(
    String id,
    UpdateServiceOrderRequest request,
  ) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.serviceOrderUpdate(id),
        data: request.toJson(),
        options: _backgroundOptions,
      );
      return ServiceOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo editar la orden');
    }
  }

  Future<void> deleteOrder(String id) async {
    try {
      await _dio.delete(
        ApiRoutes.serviceOrderDelete(id),
        options: _backgroundOptions,
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo eliminar la orden');
    }
  }

  Future<Map<String, dynamic>> purgeAllDebug() async {
    try {
      final res = await _dio.delete(
        ApiRoutes.serviceOrdersDebugPurge,
        options: _backgroundOptions,
      );
      return Map<String, dynamic>.from(
        (res.data as Map?) ?? const <String, dynamic>{},
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron limpiar las órdenes');
    }
  }

  Future<ServiceOrderModel> cloneOrder(
    String sourceOrderId,
    CloneServiceOrderRequest request,
  ) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceOrderClone(sourceOrderId),
        data: request.toJson(),
        options: _backgroundOptions,
      );
      return ServiceOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo clonar la orden');
    }
  }

  Future<ServiceOrderModel> updateStatus(
    String id,
    ServiceOrderStatus status,
  ) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.serviceOrderStatus(id),
        data: {'status': status.apiValue},
        options: _backgroundOptions,
      );
      return ServiceOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo actualizar el estado');
    }
  }

  Future<ServiceOrderModel> confirmOrder(String id) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceOrderConfirm(id),
        options: _backgroundOptions,
      );
      return ServiceOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo confirmar la orden');
    }
  }

  Future<ServiceOrderEvidenceModel> addEvidence(
    String orderId,
    CreateServiceOrderEvidenceRequest request,
  ) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceOrderEvidences(orderId),
        data: request.toJson(),
        options: _backgroundOptions,
      );
      return ServiceOrderEvidenceModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo agregar la evidencia');
    }
  }

  Future<ServiceOrderReportModel> addReport(
    String orderId,
    ServiceReportType type,
    String report,
  ) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceOrderReport(orderId),
        data: {'type': type.apiValue, 'report': report.trim()},
        options: _backgroundOptions,
      );
      return ServiceOrderReportModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo guardar el reporte');
    }
  }
}
