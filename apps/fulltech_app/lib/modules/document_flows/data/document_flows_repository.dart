import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/api/env.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../document_flow_models.dart';

final documentFlowsRepositoryProvider = Provider<DocumentFlowsRepository>((
  ref,
) {
  return DocumentFlowsRepository(ref.watch(dioProvider));
});

class DocumentFlowsRepository {
  final Dio _dio;
  static final _backgroundOptions = Options(extra: {'skipLoader': true});

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

  Future<List<OrderDocumentFlowModel>> listFlows({
    DocumentFlowStatus? status,
  }) async {
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
          .map(
            (row) =>
                OrderDocumentFlowModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los flujos documentales',
        ),
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
        _extractMessage(
          e.response?.data,
          'No se pudo cargar el flujo documental',
        ),
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
        _extractMessage(
          e.response?.data,
          'No se pudo guardar el borrador documental',
        ),
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
        _extractMessage(
          e.response?.data,
          'No se pudieron generar los documentos',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<DocumentFlowSendResult> send(
    String id, {
    String? invoicePdfBase64,
    String? warrantyPdfBase64,
    String? invoiceFileName,
    String? warrantyFileName,
  }) async {
    try {
      final response = await _dio.post(
        ApiRoutes.documentFlowSend(id),
        data: {
          if ((invoicePdfBase64 ?? '').trim().isNotEmpty)
            'invoicePdfBase64': invoicePdfBase64!.trim(),
          if ((warrantyPdfBase64 ?? '').trim().isNotEmpty)
            'warrantyPdfBase64': warrantyPdfBase64!.trim(),
          if ((invoiceFileName ?? '').trim().isNotEmpty)
            'invoiceFileName': invoiceFileName!.trim(),
          if ((warrantyFileName ?? '').trim().isNotEmpty)
            'warrantyFileName': warrantyFileName!.trim(),
        },
      );
      return DocumentFlowSendResult.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo preparar el envío documental',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteFlow(String id) async {
    try {
      await _dio.delete(ApiRoutes.documentFlowDelete(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo eliminar el flujo documental',
        ),
        e.response?.statusCode,
      );
    }
  }

  String resolveDocumentUrl(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) return '';

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      return uri.toString();
    }

    final normalized = value.replaceAll('\\', '/');
    final baseUrl = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    if (normalized.startsWith('/uploads/')) {
      return '$baseUrl$normalized';
    }
    if (normalized.startsWith('uploads/')) {
      return '$baseUrl/$normalized';
    }
    if (normalized.startsWith('./uploads/')) {
      return '$baseUrl/${normalized.substring(2)}';
    }

    return normalized.startsWith('/')
        ? '$baseUrl$normalized'
        : '$baseUrl/$normalized';
  }

  Future<Uint8List> downloadPdfBytes(String rawUrl) async {
    final resolvedUrl = resolveDocumentUrl(rawUrl);
    if (resolvedUrl.isEmpty) {
      throw ApiException('No hay un PDF disponible para visualizar');
    }

    final uri = Uri.parse(resolvedUrl);

    try {
      final response = await _dio.getUri<dynamic>(
        uri,
        options: _backgroundOptions.copyWith(responseType: ResponseType.bytes),
      );
      final bytes = _extractBytes(response.data);
      if (bytes.isNotEmpty) return bytes;
    } on DioException catch (_) {
      // Retry below with stream for environments where bytes may arrive empty.
    }

    try {
      final response = await _dio.getUri<ResponseBody>(
        uri,
        options: _backgroundOptions.copyWith(responseType: ResponseType.stream),
      );
      final body = response.data;
      if (body == null) {
        throw ApiException('El servidor no devolvió contenido PDF');
      }
      final bytes = await _collectResponseBytes(body);
      if (bytes.isEmpty) {
        throw ApiException('El PDF se recibió vacío');
      }
      return bytes;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo descargar el PDF'),
        e.response?.statusCode,
      );
    }
  }

  Uint8List _extractBytes(dynamic data) {
    if (data is Uint8List) return data;
    if (data is ByteBuffer) return data.asUint8List();
    if (data is List<int>) return Uint8List.fromList(data);
    return Uint8List(0);
  }

  Future<Uint8List> _collectResponseBytes(ResponseBody body) async {
    final bytes = <int>[];
    await for (final chunk in body.stream) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }
}
