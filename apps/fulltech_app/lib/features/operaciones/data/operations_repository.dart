import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/debug/trace_log.dart';
import '../../../core/errors/api_exception.dart';
import '../../../modules/clientes/cliente_model.dart';
import '../operations_models.dart';

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  return OperationsRepository(ref.watch(dioProvider));
});

class OperationsRepository {
  final Dio _dio;

  static const Duration _servicesCacheTtl = Duration(days: 7);
  static const Duration _dashboardCacheTtl = Duration(days: 7);
  static const Duration _serviceDetailCacheTtl = Duration(days: 7);

  final LocalJsonCache _cache = LocalJsonCache();

  OperationsRepository(this._dio);

  Map<String, dynamic> _decodeJsonMap(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    throw const FormatException('Expected JSON object');
  }

  List<TechnicianModel>? _techniciansCache;
  DateTime? _techniciansCacheAt;
  static const Duration _techniciansCacheTtl = Duration(minutes: 5);

  String _scope(String raw) {
    final v = raw.trim();
    return v.isEmpty ? 'anon' : v;
  }

  String _short(String value, {int max = 120}) {
    final v = value.trim();
    if (v.length <= max) return v;
    return v.substring(0, max);
  }

  String _servicesCacheKey({
    required String cacheScope,
    String? status,
    String? type,
    String? orderType,
    String? orderState,
    String? technicianId,
    int? priority,
    String? assignedTo,
    String? customerId,
    String? search,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) {
    return [
      'ops',
      'services',
      _scope(cacheScope),
      status ?? '',
      type ?? '',
      orderType ?? '',
      orderState ?? '',
      technicianId ?? '',
      priority?.toString() ?? '',
      assignedTo ?? '',
      customerId ?? '',
      _short(search ?? ''),
      from?.toIso8601String() ?? '',
      to?.toIso8601String() ?? '',
      page.toString(),
      pageSize.toString(),
    ].join('|');
  }

  String _dashboardCacheKey({
    required String cacheScope,
    DateTime? from,
    DateTime? to,
  }) {
    return [
      'ops',
      'dashboard',
      _scope(cacheScope),
      from?.toIso8601String() ?? '',
      to?.toIso8601String() ?? '',
    ].join('|');
  }

  String _serviceCacheKey({required String cacheScope, required String id}) {
    return ['ops', 'service', _scope(cacheScope), id.trim()].join('|');
  }

  Future<ServicesPageModel?> getCachedServices({
    required String cacheScope,
    String? status,
    String? type,
    String? orderType,
    String? orderState,
    String? technicianId,
    int? priority,
    String? assignedTo,
    String? customerId,
    String? search,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    final key = _servicesCacheKey(
      cacheScope: cacheScope,
      status: status,
      type: type,
      orderType: orderType,
      orderState: orderState,
      technicianId: technicianId,
      priority: priority,
      assignedTo: assignedTo,
      customerId: customerId,
      search: search,
      from: from,
      to: to,
      page: page,
      pageSize: pageSize,
    );
    final map = await _cache.readMap(key, maxAge: _servicesCacheTtl);
    if (map == null) return null;
    return ServicesPageModel.fromJson(map);
  }

  Future<OperationsDashboardModel?> getCachedDashboard({
    required String cacheScope,
    DateTime? from,
    DateTime? to,
  }) async {
    final key = _dashboardCacheKey(cacheScope: cacheScope, from: from, to: to);
    final map = await _cache.readMap(key, maxAge: _dashboardCacheTtl);
    if (map == null) return null;
    return OperationsDashboardModel.fromJson(map);
  }

  Future<ServiceModel?> getCachedService({
    required String cacheScope,
    required String id,
  }) async {
    final key = _serviceCacheKey(cacheScope: cacheScope, id: id);
    final map = await _cache.readMap(key, maxAge: _serviceDetailCacheTtl);
    if (map == null) return null;
    return ServiceModel.fromJson(map);
  }

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
    String? orderType,
    String? orderState,
    String? technicianId,
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
          if (orderType != null && orderType.isNotEmpty) 'orderType': orderType,
          if (orderState != null && orderState.isNotEmpty)
            'orderState': orderState,
          if (technicianId != null && technicianId.isNotEmpty)
            'technicianId': technicianId,
          if (priority != null) 'priority': priority,
          if (assignedTo != null && assignedTo.isNotEmpty)
            'assignedTo': assignedTo,
          if (customerId != null && customerId.isNotEmpty)
            'customerId': customerId,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
          'page': page,
          'pageSize': pageSize,
        },
      );
      return ServicesPageModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar servicios'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> listServicesMini({
    int page = 1,
    int pageSize = 50,
    Options? options,
  }) async {
    final seq = TraceLog.nextSeq();
    TraceLog.log(
      'OperationsRepository',
      'listServicesMini(page=$page pageSize=$pageSize) start',
      seq: seq,
    );
    try {
      if (!kIsWeb) {
        final sw = Stopwatch()..start();
        TraceLog.log(
          'OperationsRepository',
          'listServicesMini: dio.get(plain) ...',
          seq: seq,
        );
        final resPlain = await _dio
            .get(
              ApiRoutes.services,
              options: Options(
                responseType: ResponseType.plain,
                extra: {'skipLoader': true, ...?options?.extra},
              ),
              queryParameters: {'page': page, 'pageSize': pageSize},
            )
            .timeout(const Duration(seconds: 25));
        final body = resPlain.data;
        final text = body is String ? body : body.toString();
        debugPrint(
          '[OperationsRepository] Services mini (plain) recibido en ${sw.elapsedMilliseconds}ms (chars=${text.length})',
        );
        TraceLog.log(
          'OperationsRepository',
          'listServicesMini: compute(jsonDecode) ...',
          seq: seq,
        );
        final items = await compute(
          _extractServicesMiniItemsFromJson,
          text,
        ).timeout(const Duration(seconds: 20));
        TraceLog.log(
          'OperationsRepository',
          'listServicesMini end OK (count=${items.length})',
          seq: seq,
        );
        return items;
      }

      TraceLog.log(
        'OperationsRepository',
        'listServicesMini: dio.get(json) ...',
        seq: seq,
      );
      final res = await _dio
          .get(
            ApiRoutes.services,
            options: Options(extra: {'skipLoader': true, ...?options?.extra}),
            queryParameters: {'page': page, 'pageSize': pageSize},
          )
          .timeout(const Duration(seconds: 25));
      final data = res.data;
      if (data is! Map) return const <Map<String, dynamic>>[];
      final items = data['items'];
      if (items is! List) return const <Map<String, dynamic>>[];

      return items
          .whereType<Map>()
          .map(
            (e) => <String, dynamic>{
              'id': (e['id'] ?? '').toString(),
              'title': (e['title'] ?? '').toString(),
              'status': (e['status'] ?? '').toString(),
              'orderState': e['orderState']?.toString(),
              'scheduledStart': e['scheduledStart']?.toString(),
            },
          )
          .toList(growable: false);
    } on TimeoutException catch (e, st) {
      TraceLog.log(
        'OperationsRepository',
        'listServicesMini TIMEOUT',
        seq: seq,
        error: e,
        stackTrace: st,
      );
      throw ApiException('[TIMEOUT] No se pudieron cargar servicios');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar servicios'),
        e.response?.statusCode,
      );
    }
  }

  static List<Map<String, dynamic>> _extractServicesMiniItemsFromJson(
    String body,
  ) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const <Map<String, dynamic>>[];
    final items = decoded['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map>()
        .map(
          (e) => <String, dynamic>{
            'id': (e['id'] ?? '').toString(),
            'title': (e['title'] ?? '').toString(),
            'status': (e['status'] ?? '').toString(),
            'orderState': e['orderState']?.toString(),
            'scheduledStart': e['scheduledStart']?.toString(),
          },
        )
        .toList(growable: false);
  }

  Future<ServicesPageModel> listServicesAndCache({
    required String cacheScope,
    bool silent = false,
    String? status,
    String? type,
    String? orderType,
    String? orderState,
    String? technicianId,
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
        options: Options(extra: {'silent': silent}),
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
          if (type != null && type.isNotEmpty) 'type': type,
          if (orderType != null && orderType.isNotEmpty) 'orderType': orderType,
          if (orderState != null && orderState.isNotEmpty)
            'orderState': orderState,
          if (technicianId != null && technicianId.isNotEmpty)
            'technicianId': technicianId,
          if (priority != null) 'priority': priority,
          if (assignedTo != null && assignedTo.isNotEmpty)
            'assignedTo': assignedTo,
          if (customerId != null && customerId.isNotEmpty)
            'customerId': customerId,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
          'page': page,
          'pageSize': pageSize,
        },
      );

      final raw = (res.data as Map).cast<String, dynamic>();
      final key = _servicesCacheKey(
        cacheScope: cacheScope,
        status: status,
        type: type,
        orderType: orderType,
        orderState: orderState,
        technicianId: technicianId,
        priority: priority,
        assignedTo: assignedTo,
        customerId: customerId,
        search: search,
        from: from,
        to: to,
        page: page,
        pageSize: pageSize,
      );
      await _cache.writeMap(key, raw);
      return ServicesPageModel.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar servicios'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> getService(String id) async {
    try {
      final res = await _dio.get(
        ApiRoutes.serviceDetail(id),
        options: Options(responseType: ResponseType.plain),
      );

      final raw = _decodeJsonMap(res.data);
      return ServiceModel.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el servicio'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar el servicio',
      );
    }
  }

  Future<ServiceModel> getServiceAndCache({
    required String cacheScope,
    required String id,
    bool silent = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.serviceDetail(id),
        options: Options(
          extra: {'silent': silent},
          responseType: ResponseType.plain,
        ),
      );
      final raw = _decodeJsonMap(res.data);
      final key = _serviceCacheKey(cacheScope: cacheScope, id: id);
      await _cache.writeMap(key, raw);
      return ServiceModel.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el servicio'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar el servicio',
      );
    }
  }

  Future<ServiceModel> updateService({
    required String serviceId,
    String? description,
    String? addressSnapshot,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (addressSnapshot != null && addressSnapshot.trim().isNotEmpty)
          'addressSnapshot': addressSnapshot.trim(),
      };

      if (payload.isEmpty) {
        throw ApiException('No hay cambios para guardar', 400);
      }

      final res = await _dio.patch(
        ApiRoutes.serviceDetail(serviceId),
        data: payload,
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el servicio'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteService(String id) async {
    try {
      await _dio.delete(ApiRoutes.serviceDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el servicio'),
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
    String? orderType,
    String? orderState,
    String? technicianId,
    String? warrantyParentServiceId,
    String? surveyResult,
    String? materialsUsed,
    double? finalCost,
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
          if (orderType != null && orderType.trim().isNotEmpty)
            'orderType': orderType.trim(),
          if (orderState != null && orderState.trim().isNotEmpty)
            'orderState': orderState.trim(),
          if (technicianId != null && technicianId.trim().isNotEmpty)
            'technicianId': technicianId.trim(),
          if (warrantyParentServiceId != null &&
              warrantyParentServiceId.trim().isNotEmpty)
            'warrantyParentServiceId': warrantyParentServiceId.trim(),
          if (surveyResult != null && surveyResult.trim().isNotEmpty)
            'surveyResult': surveyResult.trim(),
          if (materialsUsed != null && materialsUsed.trim().isNotEmpty)
            'materialsUsed': materialsUsed.trim(),
          if (finalCost != null) 'finalCost': finalCost,
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

  Future<List<TechnicianModel>> listTechnicians() async {
    try {
      final res = await _dio.get(ApiRoutes.technicians);
      final data = (res.data as Map).cast<String, dynamic>();
      final raw = data['items'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((row) => TechnicianModel.fromJson(row.cast<String, dynamic>()))
          .where((t) => t.id.trim().isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar técnicos'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<TechnicianModel>> getTechnicians({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _techniciansCache != null &&
        _techniciansCacheAt != null) {
      final age = DateTime.now().difference(_techniciansCacheAt!);
      if (age < _techniciansCacheTtl) return _techniciansCache!;
    }

    final items = await listTechnicians();
    _techniciansCache = items;
    _techniciansCacheAt = DateTime.now();
    return items;
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

  Future<ServiceModel> changeOrderState({
    required String serviceId,
    required String orderState,
    String? message,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.serviceOrderState(serviceId),
        data: {
          'orderState': orderState,
          if (message != null && message.trim().isNotEmpty) 'message': message,
        },
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cambiar el estado'),
        e.response?.statusCode,
      );
    }
  }

  Future<ServiceModel> changePhase({
    required String serviceId,
    required String phase,
    required DateTime scheduledAt,
    String? note,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.servicePhase(serviceId),
        data: {
          'phase': phase,
          'scheduledAt': scheduledAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
      return ServiceModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cambiar la fase'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<ServicePhaseHistoryModel>> listServicePhases(
    String serviceId,
  ) async {
    try {
      final res = await _dio.get(ApiRoutes.servicePhases(serviceId));
      final raw = res.data;
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map(
            (row) =>
                ServicePhaseHistoryModel.fromJson(row.cast<String, dynamic>()),
          )
          .where((h) => h.id.trim().isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo cargar historial de fases',
        ),
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

  Future<ServiceExecutionBundleModel> getExecutionReport({
    required String serviceId,
    String? technicianId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.serviceExecutionReport(serviceId),
        options: Options(responseType: ResponseType.plain),
        queryParameters: {
          if (technicianId != null && technicianId.trim().isNotEmpty)
            'technicianId': technicianId.trim(),
        },
      );

      final raw = _decodeJsonMap(res.data);
      return ServiceExecutionBundleModel.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el reporte técnico'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException('Respuesta inválida del servidor al cargar el reporte');
    }
  }

  Future<ServiceExecutionBundleModel> upsertExecutionReport({
    required String serviceId,
    String? technicianId,
    String? phase,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? notes,
    Map<String, dynamic>? checklistData,
    Map<String, dynamic>? phaseSpecificData,
    bool? clientApproved,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (technicianId != null && technicianId.trim().isNotEmpty)
          'technicianId': technicianId.trim(),
        if (phase != null && phase.trim().isNotEmpty) 'phase': phase.trim(),
        if (arrivedAt != null) 'arrivedAt': arrivedAt.toIso8601String(),
        if (startedAt != null) 'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt.toIso8601String(),
        if (notes != null) 'notes': notes,
        if (checklistData != null) 'checklistData': checklistData,
        if (phaseSpecificData != null) 'phaseSpecificData': phaseSpecificData,
        if (clientApproved != null) 'clientApproved': clientApproved,
      };

      final res = await _dio.put(
        ApiRoutes.serviceExecutionReport(serviceId),
        data: payload,
        options: Options(responseType: ResponseType.plain),
      );

      final raw = _decodeJsonMap(res.data);
      return ServiceExecutionBundleModel.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el reporte técnico'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException('Respuesta inválida del servidor al guardar el reporte');
    }
  }

  Future<ServiceExecutionChangeModel> addExecutionChange({
    required String serviceId,
    required String type,
    required String description,
    double? quantity,
    double? extraCost,
    bool? clientApproved,
    String? note,
  }) async {
    try {
      final payload = <String, dynamic>{
        'type': type,
        'description': description,
        if (quantity != null) 'quantity': quantity,
        if (extraCost != null) 'extraCost': extraCost,
        if (clientApproved != null) 'clientApproved': clientApproved,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      };

      final res = await _dio.post(
        ApiRoutes.serviceExecutionChanges(serviceId),
        data: payload,
      );

      return ServiceExecutionChangeModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo agregar el cambio'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteExecutionChange({
    required String serviceId,
    required String changeId,
  }) async {
    try {
      await _dio.delete(
        ApiRoutes.serviceExecutionChangeDelete(serviceId, changeId),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el cambio'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> uploadEvidence({
    required String serviceId,
    required PlatformFile file,
  }) async {
    try {
      final MultipartFile multipart;
      if (file.bytes != null) {
        multipart = MultipartFile.fromBytes(file.bytes!, filename: file.name);
      } else if (file.path != null && file.path!.trim().isNotEmpty) {
        multipart = await MultipartFile.fromFile(
          file.path!,
          filename: file.name,
        );
      } else {
        throw ApiException('Archivo inválido para subir evidencia');
      }

      final form = FormData.fromMap({'file': multipart});
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

  Future<OperationsDashboardModel> dashboardAndCache({
    required String cacheScope,
    DateTime? from,
    DateTime? to,
    bool silent = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.operationsDashboard,
        options: Options(extra: {'silent': silent}),
        queryParameters: {
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
        },
      );
      final raw = (res.data as Map).cast<String, dynamic>();
      final key = _dashboardCacheKey(
        cacheScope: cacheScope,
        from: from,
        to: to,
      );
      await _cache.writeMap(key, raw);
      return OperationsDashboardModel.fromJson(raw);
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
        _extractMessage(
          e.response?.data,
          'No se pudo cargar historial del cliente',
        ),
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
