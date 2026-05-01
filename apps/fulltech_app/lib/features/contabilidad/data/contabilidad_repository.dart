import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/close_model.dart';
import '../models/deposit_order_model.dart';
import '../models/fiscal_invoice_model.dart';
import '../models/payable_models.dart';

final contabilidadRepositoryProvider = Provider<ContabilidadRepository>((ref) {
  return ContabilidadRepository(ref.watch(dioProvider));
});

class ContabilidadRepository {
  final Dio _dio;

  ContabilidadRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
    }
    return fallback;
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<List<CloseModel>> listCloses({
    required DateTime from,
    required DateTime to,
    CloseType? type,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadCloses,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if (type != null) 'type': type.apiValue,
        },
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => CloseModel.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar los cierres'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> createClose({
    required CloseType type,
    required DateTime date,
    required double cash,
    required double transfer,
    String? transferBank,
    required double card,
    double otherIncome = 0,
    required double expenses,
    required double cashDelivered,
    String? notes,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadCloses,
        data: {
          'type': type.apiValue,
          'date': date.toIso8601String(),
          'cash': cash,
          'transfer': transfer,
          if (transfer > 0) 'transferBank': transferBank?.trim(),
          'card': card,
          'otherIncome': otherIncome,
          'expenses': expenses,
          'cashDelivered': cashDelivered,
          if (notes != null) 'notes': notes.trim(),
        },
      );
      return CloseModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> updateClose({
    required String id,
    required double cash,
    required double transfer,
    String? transferBank,
    required double card,
    required double otherIncome,
    required double expenses,
    required double cashDelivered,
    String? notes,
  }) async {
    try {
      final res = await _dio.put(
        ApiRoutes.contabilidadCloseDetail(id),
        data: {
          'cash': cash,
          'transfer': transfer,
          'transferBank': transfer > 0 ? transferBank?.trim() : null,
          'card': card,
          'otherIncome': otherIncome,
          'expenses': expenses,
          'cashDelivered': cashDelivered,
          if (notes != null) 'notes': notes.trim(),
        },
      );
      return CloseModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteClose(String id) async {
    try {
      await _dio.delete(ApiRoutes.contabilidadCloseDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> approveClose(String id) async {
    final res = await _dio.post(ApiRoutes.contabilidadCloseApprove(id));
    return CloseModel.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<CloseModel> rejectClose(String id) async {
    final res = await _dio.post(ApiRoutes.contabilidadCloseReject(id));
    return CloseModel.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<DepositOrderModel> createDepositOrder({
    required DateTime windowFrom,
    required DateTime windowTo,
    required String bankName,
    String? bankAccount,
    String? collaboratorName,
    String? note,
    required double reserveAmount,
    required double totalAvailableCash,
    required double depositTotal,
    required Map<String, int> closesCountByType,
    required Map<String, double> depositByType,
    required Map<String, String> accountByType,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadDepositOrders,
        data: {
          'windowFrom': windowFrom.toIso8601String(),
          'windowTo': windowTo.toIso8601String(),
          'bankName': bankName,
          if (bankAccount != null && bankAccount.trim().isNotEmpty)
            'bankAccount': bankAccount.trim(),
          if (collaboratorName != null && collaboratorName.trim().isNotEmpty)
            'collaboratorName': collaboratorName.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          'reserveAmount': reserveAmount,
          'totalAvailableCash': totalAvailableCash,
          'depositTotal': depositTotal,
          'closesCountByType': closesCountByType,
          'depositByType': depositByType,
          'accountByType': accountByType,
        },
      );
      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo registrar la orden de depósito en nube',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<DepositOrderModel>> listDepositOrders({
    DateTime? from,
    DateTime? to,
    DepositOrderStatus? status,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadDepositOrders,
        queryParameters: {
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          if (status != null) 'status': status.apiValue,
        },
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => DepositOrderModel.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los depósitos',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> getDepositOrder(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.contabilidadDepositOrderDetail(id));
      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> updateDepositOrder({
    required String id,
    DateTime? windowFrom,
    DateTime? windowTo,
    String? bankName,
    String? bankAccount,
    String? collaboratorName,
    String? note,
    double? reserveAmount,
    double? totalAvailableCash,
    double? depositTotal,
    Map<String, int>? closesCountByType,
    Map<String, double>? depositByType,
    Map<String, String>? accountByType,
    DepositOrderStatus? status,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (windowFrom != null) 'windowFrom': windowFrom.toIso8601String(),
        if (windowTo != null) 'windowTo': windowTo.toIso8601String(),
        if (bankName != null) 'bankName': bankName.trim(),
        if (bankAccount != null) 'bankAccount': bankAccount.trim(),
        if (collaboratorName != null)
          'collaboratorName': collaboratorName.trim(),
        if (note != null) 'note': note.trim(),
        if (reserveAmount != null) 'reserveAmount': reserveAmount,
        if (totalAvailableCash != null)
          'totalAvailableCash': totalAvailableCash,
        if (depositTotal != null) 'depositTotal': depositTotal,
        if (closesCountByType != null) 'closesCountByType': closesCountByType,
        if (depositByType != null) 'depositByType': depositByType,
        if (accountByType != null) 'accountByType': accountByType,
        if (status != null) 'status': status.apiValue,
      };
      final res = await _dio.put(
        ApiRoutes.contabilidadDepositOrderDetail(id),
        data: payload,
      );

      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteDepositOrder(String id) async {
    try {
      await _dio.delete(ApiRoutes.contabilidadDepositOrderDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> uploadDepositVoucher({
    required String id,
    required PlatformFile file,
  }) async {
    try {
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw ApiException('No se pudo leer el voucher seleccionado');
      }

      final ext = (file.extension ?? '').toLowerCase();
      final mediaType = ext == 'pdf'
          ? MediaType('application', 'pdf')
          : ext == 'png'
          ? MediaType('image', 'png')
          : ext == 'webp'
          ? MediaType('image', 'webp')
          : MediaType('image', 'jpeg');

      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          file.bytes!,
          filename: file.name,
          contentType: mediaType,
        ),
      });

      final res = await _dio.post(
        '${ApiRoutes.contabilidadDepositOrderDetail(id)}/voucher',
        data: form,
      );

      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir el voucher'),
        e.response?.statusCode,
      );
    }
  }

  Future<String> uploadFiscalInvoiceImage(PlatformFile file) async {
    try {
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw ApiException('No se pudo leer la imagen seleccionada');
      }

      final ext = (file.extension ?? '').toLowerCase();
      final mediaType = ext == 'png'
          ? MediaType('image', 'png')
          : ext == 'webp'
          ? MediaType('image', 'webp')
          : MediaType('image', 'jpeg');

      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          file.bytes!,
          filename: file.name,
          contentType: mediaType,
        ),
      });

      final res = await _dio.post(
        ApiRoutes.contabilidadFiscalInvoicesUpload,
        data: form,
      );

      final url = (res.data is Map ? res.data['url'] : null) as String?;
      if (url == null || url.trim().isEmpty) {
        throw ApiException('La API no devolvió URL de imagen');
      }
      return url.trim();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo subir la imagen de la factura',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<FiscalInvoiceModel> createFiscalInvoice({
    required FiscalInvoiceKind kind,
    required DateTime invoiceDate,
    required String imageUrl,
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadFiscalInvoices,
        data: {
          'kind': kind.apiValue,
          'invoiceDate': invoiceDate.toIso8601String(),
          'imageUrl': imageUrl,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );

      return FiscalInvoiceModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo guardar la factura fiscal',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<FiscalInvoiceModel>> listFiscalInvoices({
    required DateTime from,
    required DateTime to,
    FiscalInvoiceKind? kind,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadFiscalInvoices,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if (kind != null) 'kind': kind.apiValue,
        },
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (row) => FiscalInvoiceModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar las facturas fiscales',
        ),
        e.response?.statusCode,
      );
    }
  }

  // --- Pagos pendientes (Payables) ---

  Future<PayableService> createPayableService({
    required String title,
    required PayableProviderKind providerKind,
    required String providerName,
    String? description,
    required PayableFrequency frequency,
    double? defaultAmount,
    required DateTime nextDueDate,
    bool active = true,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadPayableServices,
        data: {
          'title': title.trim(),
          'providerKind': providerKind.apiValue,
          'providerName': providerName.trim(),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          'frequency': frequency.apiValue,
          if (defaultAmount != null) 'defaultAmount': defaultAmount,
          'nextDueDate': nextDueDate.toIso8601String(),
          'active': active,
        },
      );

      return PayableService.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo crear el servicio por pagar',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PayableService>> listPayableServices({bool? active}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadPayableServices,
        queryParameters: {if (active != null) 'active': active},
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => PayableService.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los servicios por pagar',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<PayablePayment> registerPayablePayment({
    required String serviceId,
    required double amount,
    DateTime? paidAt,
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadPayableServicePayments(serviceId),
        data: {
          'amount': amount,
          if (paidAt != null) 'paidAt': paidAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );

      return PayablePayment.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo registrar el pago'),
        e.response?.statusCode,
      );
    }
  }

  Future<PayableService> updatePayableService({
    required String id,
    String? title,
    PayableProviderKind? providerKind,
    String? providerName,
    String? description,
    PayableFrequency? frequency,
    double? defaultAmount,
    DateTime? nextDueDate,
    bool? active,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (title != null) 'title': title.trim(),
        if (providerKind != null) 'providerKind': providerKind.apiValue,
        if (providerName != null) 'providerName': providerName.trim(),
        if (description != null) 'description': description,
        if (frequency != null) 'frequency': frequency.apiValue,
        if (defaultAmount != null) 'defaultAmount': defaultAmount,
        if (nextDueDate != null) 'nextDueDate': nextDueDate.toIso8601String(),
        if (active != null) 'active': active,
      };
      final res = await _dio.put(
        ApiRoutes.contabilidadPayableServiceDetail(id),
        data: payload,
      );

      return PayableService.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo actualizar el servicio por pagar',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PayablePayment>> listPayablePayments({
    DateTime? from,
    DateTime? to,
    String? serviceId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadPayablePayments,
        queryParameters: {
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          if (serviceId != null && serviceId.trim().isNotEmpty)
            'serviceId': serviceId,
        },
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => PayablePayment.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo cargar el historial de pagos',
        ),
        e.response?.statusCode,
      );
    }
  }
}
