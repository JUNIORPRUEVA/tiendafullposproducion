import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../document_flow_models.dart';

final documentFlowsRepositoryProvider = Provider<DocumentFlowsRepository>((ref) {
  return DocumentFlowsRepository(ref.watch(dioProvider));
});

class DocumentFlowsRepository {
  final Dio _dio;

  DocumentFlowsRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data.trim();
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
      if (message is List) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
    }
    return fallback;
  }

  Future<List<OrderDocumentFlowModel>> listFlows({DocumentFlowStatus? status}) async {
    try {
      final response = await _dio.get(
        ApiRoutes.documentFlows,
        queryParameters: {
          if (status != null) 'status': documentFlowStatusApiValue(status),
        },
      );
      final rows = response.data is List ? response.data as List : const [];
      return rows
          .whereType<Map>()
          .map((row) => OrderDocumentFlowModel.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar los flujos documentales'),
        e.response?.statusCode,
      );
    }
  }

  Future<OrderDocumentFlowModel> getByOrderId(String orderId) async {
    try {
      final response = await _dio.get(ApiRoutes.documentFlowByOrder(orderId));
      return OrderDocumentFlowModel.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el flujo documental'),
        e.response?.statusCode,
      );
    }
  }

  Future<OrderDocumentFlowModel> editDraft({
    required String id,
    required Map<String, dynamic> invoiceDraftJson,
    required Map<String, dynamic> warrantyDraftJson,
  }) async {
    try {
      final response = await _dio.patch(
        ApiRoutes.documentFlowEditDraft(id),
        data: {
          'invoiceDraftJson': invoiceDraftJson,
          'warrantyDraftJson': warrantyDraftJson,
        },
      );
      return OrderDocumentFlowModel.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el borrador documental'),
        e.response?.statusCode,
      );
    }
  }

  Future<OrderDocumentFlowModel> generate(String id) async {
    try {
      final response = await _dio.post(ApiRoutes.documentFlowGenerate(id));
      return OrderDocumentFlowModel.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron generar los documentos'),
        e.response?.statusCode,
      );
    }
  }

  Future<DocumentFlowSendResult> send(String id) async {
    try {
      final response = await _dio.post(ApiRoutes.documentFlowSend(id));
      return DocumentFlowSendResult.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo preparar el envío documental'),
        e.response?.statusCode,
      );
    }
  }
}