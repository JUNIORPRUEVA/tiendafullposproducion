import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../service_order_models.dart';

final serviceOrdersApiProvider = Provider<ServiceOrdersApi>((ref) {
  return ServiceOrdersApi(ref.watch(dioProvider));
});

class ServiceOrdersApi {
  final Dio _dio;

  ServiceOrdersApi(this._dio);

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

  Never _rethrow(DioException error, String fallback) {
    throw ApiException(
      _extractMessage(error.response?.data, fallback),
      error.response?.statusCode,
    );
  }

  Future<List<ServiceOrderModel>> listOrders() async {
    try {
      final res = await _dio.get(ApiRoutes.serviceOrders);
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
      _rethrow(error, 'No se pudieron cargar las órdenes');
    }
  }

  Future<ServiceOrderModel> getOrder(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.serviceOrderDetail(id));
      return ServiceOrderModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la orden');
    }
  }

  Future<ServiceOrderModel> createOrder(CreateServiceOrderRequest request) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceOrders,
        data: request.toJson(),
      );
      return ServiceOrderModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo crear la orden');
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
      );
      return ServiceOrderModel.fromJson((res.data as Map).cast<String, dynamic>());
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
      );
      return ServiceOrderModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo actualizar el estado');
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
      );
      return ServiceOrderEvidenceModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo agregar la evidencia');
    }
  }

  Future<ServiceOrderReportModel> addReport(String orderId, String report) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceOrderReport(orderId),
        data: {'report': report.trim()},
      );
      return ServiceOrderReportModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo guardar el reporte');
    }
  }
}