import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../modules/clientes/cliente_model.dart';
import '../operations_models.dart';

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  return OperationsRepository(ref.watch(dioProvider));
});

class OperationsRepository {
  final Dio _dio;

  OperationsRepository(this._dio);

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

  Future<ServicesPageModel> listServices({
    String? status,
    String? type,
    int? priority,
    String? assignedTo,
    String? customerId,
    String? search,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.services,
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
          if (type != null && type.isNotEmpty) 'type': type,
          if (priority != null) 'priority': priority,
          if (assignedTo != null && assignedTo.isNotEmpty) 'assignedTo': assignedTo,
          if (customerId != null && customerId.isNotEmpty) 'customerId': customerId,
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
          'page': page,
          'pageSize': pageSize,
        },
      );
      return ServicesPageModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar servicios'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> getService(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.serviceDetail(id));
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el servicio'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> createService({
    required String customerId,
    required String serviceType,
    required String category,
    required int priority,
    required String title,
    required String description,
    String? addressSnapshot,
    double? quotedAmount,
    double? depositAmount,
    List<String>? tags,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.services,
        data: {
          'customerId': customerId,
          'serviceType': serviceType,
          'category': category,
          'priority': priority,
          'title': title,
          'description': description,
          if (addressSnapshot != null && addressSnapshot.trim().isNotEmpty)
            'addressSnapshot': addressSnapshot.trim(),
          if (quotedAmount != null) 'quotedAmount': quotedAmount,
          if (depositAmount != null) 'depositAmount': depositAmount,
          if (tags != null && tags.isNotEmpty) 'tags': tags,
        },
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear la reserva'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> changeStatus({
    required String serviceId,
    required String status,
    String? message,
    bool force = false,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.serviceStatus(serviceId),
        data: {
          'status': status,
          if (message != null && message.trim().isNotEmpty) 'message': message,
          if (force) 'force': true,
        },
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cambiar estado'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> schedule({
    required String serviceId,
    required DateTime start,
    required DateTime end,
    String? message,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.serviceSchedule(serviceId),
        data: {
          'scheduledStart': start.toIso8601String(),
          'scheduledEnd': end.toIso8601String(),
          if (message != null && message.trim().isNotEmpty) 'message': message,
        },
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo agendar el servicio'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> assign({
    required String serviceId,
    required List<Map<String, String>> assignments,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceAssign(serviceId),
        data: {'assignments': assignments},
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo asignar técnicos'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> addUpdate({
    required String serviceId,
    required String type,
    String? message,
    String? stepId,
    bool? stepDone,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.serviceUpdate(serviceId),
        data: {
          'type': type,
          if (message != null && message.trim().isNotEmpty) 'message': message,
          if (stepId != null) 'stepId': stepId,
          if (stepDone != null) 'stepDone': stepDone,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar actualización'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> uploadEvidence({
    required String serviceId,
    required PlatformFile file,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          file.bytes!,
          filename: file.name,
        ),
      });
      await _dio.post(ApiRoutes.serviceFiles(serviceId), data: form);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir evidencia'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> createWarranty({
    required String serviceId,
    String? title,
    String? description,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.serviceWarranty(serviceId),
        data: {
          if (title != null && title.trim().isNotEmpty) 'title': title,
          if (description != null && description.trim().isNotEmpty)
            'description': description,
        },
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear garantía'),
        e.response?.statusCode,
      );
    }
  }

  Future<OperationsDashboardModel> dashboard({
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.operationsDashboard,
        queryParameters: {
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
        },
      );
      return OperationsDashboardModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar dashboard'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<ServiceModel>> customerServices(String customerId) async {
    try {
      final res = await _dio.get(ApiRoutes.customerServices(customerId));
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => ServiceModel.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar historial del cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<ClienteModel>> searchClients(String search) async {
    try {
      final res = await _dio.get(
        ApiRoutes.clients,
        queryParameters: {
          if (search.trim().isNotEmpty) 'search': search.trim(),
          'page': 1,
          'pageSize': 20,
        },
      );
      final raw = res.data;
      final List<dynamic> rows;
      if (raw is List) {
        rows = raw;
      } else if (raw is Map && raw['items'] is List) {
        rows = raw['items'] as List<dynamic>;
      } else {
        rows = const [];
      }

      return rows
          .whereType<Map>()
          .map((row) => ClienteModel.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar clientes'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClienteModel> createQuickClient({
    required String nombre,
    required String telefono,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.clients,
        data: {'nombre': nombre.trim(), 'telefono': telefono.trim()},
      );
      return ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el cliente'),
        e.response?.statusCode,
      );
    }
  }
}
