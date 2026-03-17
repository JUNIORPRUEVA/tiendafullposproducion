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
import '../../../core/offline/sync_queue_service.dart';
import '../../../modules/clientes/cliente_model.dart';
import '../operations_models.dart';
import '../tecnico/technical_visit_models.dart';

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  final repository = OperationsRepository(
    ref.watch(dioProvider),
    ref.read(syncQueueServiceProvider.notifier),
  );
  repository.registerSyncHandlers();
  return repository;
});

class OperationsRepository {
  final Dio _dio;
  final SyncQueueService _syncQueue;

  static const Duration _servicesCacheTtl = Duration(days: 7);
  static const Duration _dashboardCacheTtl = Duration(days: 7);
  static const Duration _serviceDetailCacheTtl = Duration(days: 7);
  static const Duration _techServicesCacheTtl = Duration(minutes: 2);
  static const Duration _executionReportCacheTtl = Duration(days: 3);
  static const Duration _serviceChecklistCacheTtl = Duration(days: 7);
  static const Duration _technicalVisitCacheTtl = Duration(days: 3);

  final LocalJsonCache _cache = LocalJsonCache();
  bool _handlersRegistered = false;

  static const String _checkChecklistSyncType = 'operations.checklist_item';
  static const String _saveExecutionReportSyncType =
      'operations.execution_report';
  static const String _saveTechnicalVisitSyncType =
      'operations.technical_visit';

  OperationsRepository(this._dio, this._syncQueue);

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;

    _syncQueue.registerHandler(_checkChecklistSyncType, (payload) async {
      await checkServiceChecklistItem(
        itemId: (payload['itemId'] ?? '').toString(),
        isChecked: payload['isChecked'] == true,
      );
    });

    _syncQueue.registerHandler(_saveExecutionReportSyncType, (payload) async {
      await upsertExecutionReport(
        serviceId: (payload['serviceId'] ?? '').toString(),
        technicianId: payload['technicianId']?.toString(),
        phase: payload['phase']?.toString(),
        arrivedAt: _dateOrNull(payload['arrivedAt']),
        startedAt: _dateOrNull(payload['startedAt']),
        finishedAt: _dateOrNull(payload['finishedAt']),
        notes: payload['notes']?.toString(),
        checklistData: (payload['checklistData'] as Map?)?.cast<String, dynamic>(),
        phaseSpecificData:
            (payload['phaseSpecificData'] as Map?)?.cast<String, dynamic>(),
        clientApproved: payload['clientApproved'] as bool?,
      );
    });

    _syncQueue.registerHandler(_saveTechnicalVisitSyncType, (payload) async {
      final visitId = (payload['visitId'] ?? '').toString().trim();
      final rawPayload = ((payload['payload'] as Map?) ?? const <String, dynamic>{})
          .cast<String, dynamic>();
      if (visitId.isEmpty) {
        await createTechnicalVisit(payload: rawPayload);
      } else {
        await updateTechnicalVisit(id: visitId, payload: rawPayload);
      }
    });
  }

  static DateTime? _dateOrNull(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  bool _shouldQueueSync(ApiException error) {
    final code = error.code;
    return code == null || code >= 500;
  }

  Map<String, dynamic> _executionReportToMap(
    ServiceExecutionReportModel report,
  ) {
    return {
      'id': report.id,
      'serviceId': report.serviceId,
      'technicianId': report.technicianId,
      'phase': report.phase,
      'arrivedAt': report.arrivedAt?.toIso8601String(),
      'startedAt': report.startedAt?.toIso8601String(),
      'finishedAt': report.finishedAt?.toIso8601String(),
      'notes': report.notes,
      'checklistData': report.checklistData,
      'phaseSpecificData': report.phaseSpecificData,
      'clientApproved': report.clientApproved,
      'updatedAt': report.updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _executionChangeToMap(
    ServiceExecutionChangeModel change,
  ) {
    return {
      'id': change.id,
      'serviceId': change.serviceId,
      'executionReportId': change.executionReportId,
      'createdByUserId': change.createdByUserId,
      'type': change.type,
      'description': change.description,
      'quantity': change.quantity,
      'extraCost': change.extraCost,
      'clientApproved': change.clientApproved,
      'note': change.note,
      'createdAt': change.createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _executionBundleToMap(
    ServiceExecutionBundleModel bundle,
  ) {
    return {
      'report': bundle.report == null ? null : _executionReportToMap(bundle.report!),
      'changes': bundle.changes
          .map((change) => _executionChangeToMap(change))
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _checklistCategoryToMap(
    ServiceChecklistCategoryModel category,
  ) {
    return {'id': category.id, 'name': category.name, 'code': category.code};
  }

  Map<String, dynamic> _checklistPhaseToMap(ServiceChecklistPhaseModel phase) {
    return {
      'id': phase.id,
      'name': phase.name,
      'code': phase.code,
      'orderIndex': phase.orderIndex,
    };
  }

  Map<String, dynamic> _checklistItemToMap(ServiceChecklistItemModel item) {
    return {
      'id': item.id,
      'checklistItemId': item.checklistItemId,
      'label': item.label,
      'isRequired': item.isRequired,
      'orderIndex': item.orderIndex,
      'isChecked': item.isChecked,
      'checkedAt': item.checkedAt?.toIso8601String(),
      'checkedByUserId': item.checkedByUserId,
      'checkedByName': item.checkedByName,
    };
  }

  Map<String, dynamic> _checklistTemplateToMap(
    ServiceChecklistTemplateModel template,
  ) {
    return {
      'id': template.id,
      'templateId': template.templateId,
      'type': serviceChecklistSectionTypeCode(template.type),
      'title': template.title,
      'category': _checklistCategoryToMap(template.category),
      'phase': _checklistPhaseToMap(template.phase),
      'items': template.items
          .map((item) => _checklistItemToMap(item))
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _checklistBundleToMap(
    ServiceChecklistBundleModel bundle,
  ) {
    return {
      'serviceId': bundle.serviceId,
      'currentPhase': bundle.currentPhase,
      'orderState': bundle.orderState,
      'category': {
        'code': bundle.categoryCode,
        'label': bundle.categoryLabel,
      },
      'templates': bundle.templates
          .map((template) => _checklistTemplateToMap(template))
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _technicalVisitToMap(TechnicalVisitModel visit) {
    return {
      'id': visit.id,
      'orderId': visit.orderId,
      'technicianId': visit.technicianId,
      'reportDescription': visit.reportDescription,
      'installationNotes': visit.installationNotes,
      'estimatedProducts': visit.estimatedProducts
          .map((item) => item.toJson())
          .toList(growable: false),
      'photos': visit.photos,
      'videos': visit.videos,
      'visitDate': visit.visitDate?.toIso8601String(),
      'createdAt': visit.createdAt?.toIso8601String(),
      'updatedAt': visit.updatedAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> _decodeJsonMap(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    }
    throw const FormatException('Expected JSON object');
  }

  List<dynamic> _decodeJsonList(dynamic data) {
    if (data is List) return data;
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is List) return decoded;
    }
    throw const FormatException('Expected JSON array');
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

  String _executionReportCacheKey({
    required String cacheScope,
    required String serviceId,
    String? technicianId,
  }) {
    return [
      'ops',
      'execution_report',
      _scope(cacheScope),
      serviceId.trim(),
      (technicianId ?? '').trim(),
    ].join('|');
  }

  String _serviceChecklistCacheKey({
    required String cacheScope,
    required String serviceId,
  }) {
    return ['ops', 'service_checklist', _scope(cacheScope), serviceId.trim()]
        .join('|');
  }

  String _templateChecklistCacheKey({
    required String cacheScope,
    required String categoryId,
    required String phaseId,
  }) {
    return [
      'ops',
      'checklist_templates',
      _scope(cacheScope),
      categoryId.trim(),
      phaseId.trim(),
    ].join('|');
  }

  String _technicalVisitCacheKey({
    required String cacheScope,
    required String orderId,
  }) {
    return ['ops', 'technical_visit', _scope(cacheScope), orderId.trim()]
        .join('|');
  }

  String _techServicesCacheKey({
    required String cacheScope,
    required String techKey,
  }) {
    return [
      'ops',
      'tech_services',
      _scope(cacheScope),
      techKey.trim(),
    ].join('|');
  }

  Future<List<ServiceModel>?> getCachedTechServices({
    required String cacheScope,
    required String techKey,
  }) async {
    final key = _techServicesCacheKey(cacheScope: cacheScope, techKey: techKey);
    final map = await _cache.readMap(key, maxAge: _techServicesCacheTtl);
    if (map == null) return null;
    final rawItems = map['items'];
    if (rawItems is! List) return null;

    final items = <ServiceModel>[];
    for (final row in rawItems) {
      if (row is Map) {
        try {
          items.add(ServiceModel.fromJson(row.cast<String, dynamic>()));
        } catch (_) {
          // ignore invalid rows
        }
      }
    }
    return items;
  }

  Future<List<Map<String, dynamic>>> _listServicesItemsRaw({
    bool silent = false,
    String? status,
    String? technicianId,
    String? assignedTo,
    int page = 1,
    int pageSize = 200,
  }) async {
    final res = await _dio.get(
      ApiRoutes.services,
      options: Options(extra: {'silent': silent}),
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (technicianId != null && technicianId.isNotEmpty)
          'technicianId': technicianId,
        if (assignedTo != null && assignedTo.isNotEmpty)
          'assignedTo': assignedTo,
        'page': page,
        'pageSize': pageSize,
      },
    );

    final data = (res.data as Map).cast<String, dynamic>();
    final items = data['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<List<ServiceModel>> listTechServicesAndCache({
    required String cacheScope,
    required String techKey,
    required String? technicianId,
    required String? assignedTo,
    bool silent = false,
  }) async {
    final key = _techServicesCacheKey(cacheScope: cacheScope, techKey: techKey);

    Object? lastError;
    var okRequests = 0;

    const statuses = <String>[
      'survey',
      'scheduled',
      'in_progress',
      'warranty',
      'pending',
      'completed',
      'closed',
      'cancelled',
    ];

    Future<List<Map<String, dynamic>>> safeList({
      required String? status,
      required String? technicianId,
      required String? assignedTo,
    }) async {
      try {
        final items = await _listServicesItemsRaw(
          silent: silent,
          status: status,
          technicianId: technicianId,
          assignedTo: assignedTo,
          page: 1,
          pageSize: 200,
        );
        okRequests++;
        return items;
      } catch (e) {
        lastError = e;
        return const <Map<String, dynamic>>[];
      }
    }

    // Fast path: some deployments accept listing without status.
    var mergedRaw = await safeList(
      status: null,
      technicianId: technicianId,
      assignedTo: assignedTo,
    );

    // If empty, do the more expensive per-status strategy in parallel.
    if (mergedRaw.isEmpty) {
      final batches = await Future.wait(
        statuses
            .map(
              (s) => safeList(
                status: s,
                technicianId: technicianId,
                assignedTo: assignedTo,
              ),
            )
            .toList(growable: false),
        eagerError: false,
      );
      mergedRaw = batches.expand((e) => e).toList(growable: false);
    }

    // Fallback: if filters yield nothing, try without them.
    if (mergedRaw.isEmpty &&
        technicianId != null &&
        technicianId.trim().isNotEmpty) {
      final batches = await Future.wait(
        statuses
            .map(
              (s) => safeList(status: s, technicianId: null, assignedTo: null),
            )
            .toList(growable: false),
        eagerError: false,
      );
      mergedRaw = batches.expand((e) => e).toList(growable: false);
      if (mergedRaw.isEmpty) {
        mergedRaw = await safeList(
          status: null,
          technicianId: null,
          assignedTo: null,
        );
      }
    }

    // If every request failed (auth/network/server), surface the error instead
    // of returning an empty list that looks like “no services”.
    if (mergedRaw.isEmpty && okRequests == 0 && lastError != null) {
      throw lastError!;
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final row in mergedRaw) {
      final id = (row['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      byId[id] = row;
    }
    final deduped = byId.values.toList(growable: false);

    await _cache.writeMap(key, {'items': deduped});

    return deduped
        .map((row) => ServiceModel.fromJson(row))
        .toList(growable: false);
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

  Future<ServiceExecutionBundleModel?> getCachedExecutionReport({
    required String cacheScope,
    required String serviceId,
    String? technicianId,
  }) async {
    final map = await _cache.readMap(
      _executionReportCacheKey(
        cacheScope: cacheScope,
        serviceId: serviceId,
        technicianId: technicianId,
      ),
      maxAge: _executionReportCacheTtl,
    );
    if (map == null) return null;
    return ServiceExecutionBundleModel.fromJson(map);
  }

  Future<ServiceChecklistBundleModel?> getCachedServiceChecklists({
    required String cacheScope,
    required String serviceId,
  }) async {
    final map = await _cache.readMap(
      _serviceChecklistCacheKey(cacheScope: cacheScope, serviceId: serviceId),
      maxAge: _serviceChecklistCacheTtl,
    );
    if (map == null) return null;
    return ServiceChecklistBundleModel.fromJson(map);
  }

  Future<List<ServiceChecklistTemplateModel>?> getCachedChecklistTemplates({
    required String cacheScope,
    required String categoryId,
    required String phaseId,
  }) async {
    final map = await _cache.readMap(
      _templateChecklistCacheKey(
        cacheScope: cacheScope,
        categoryId: categoryId,
        phaseId: phaseId,
      ),
      maxAge: _serviceChecklistCacheTtl,
    );
    final raw = map?['items'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map(
          (item) => ServiceChecklistTemplateModel.fromJson(
            item.cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  Future<TechnicalVisitModel?> getCachedTechnicalVisitByOrder({
    required String cacheScope,
    required String orderId,
  }) async {
    final map = await _cache.readMap(
      _technicalVisitCacheKey(cacheScope: cacheScope, orderId: orderId),
      maxAge: _technicalVisitCacheTtl,
    );
    if (map == null) return null;
    return TechnicalVisitModel.fromJson(map);
  }

  Future<void> upsertServiceCacheFromRealtime({
    required String cacheScope,
    required Map<String, dynamic> serviceJson,
  }) async {
    final id = (serviceJson['id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    final key = _serviceCacheKey(cacheScope: cacheScope, id: id);
    await _cache.writeMap(key, serviceJson);
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return _extractMessage(decoded.cast<String, dynamic>(), data.trim());
        }
      } catch (_) {
        // Not JSON; return as-is.
      }
      return data.trim();
    }
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

  String _formatDioError(DioException e, String fallback) {
    final status = e.response?.statusCode;
    final rawMessage = _extractMessage(e.response?.data, fallback);
    final uri = e.requestOptions.uri.toString();
    final baseUrl = _dio.options.baseUrl;

    if (status == null) {
      final webHint = kIsWeb
          ? '\nWeb: revisa API_BASE_URL (https vs http), CORS del backend, y que el servidor esté accesible desde el navegador.'
          : '';
      return '[NETWORK] $rawMessage\nURI: $uri\nBaseURL: $baseUrl\nDetalle: ${e.message ?? 'Sin respuesta del servidor'}$webHint';
    }

    return '[HTTP $status] $rawMessage\nURI: $uri';
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
        _formatDioError(e, 'No se pudo cargar el servicio'),
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
        _formatDioError(e, 'No se pudo cargar el servicio'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar el servicio',
      );
    }
  }

  Future<ServiceExecutionBundleModel> getExecutionReportAndCache({
    required String cacheScope,
    required String serviceId,
    String? technicianId,
  }) async {
    final bundle = await getExecutionReport(
      serviceId: serviceId,
      technicianId: technicianId,
    );
    await _cache.writeMap(
      _executionReportCacheKey(
        cacheScope: cacheScope,
        serviceId: serviceId,
        technicianId: technicianId,
      ),
      _executionBundleToMap(bundle),
    );
    return bundle;
  }

  Future<ServiceChecklistBundleModel> getServiceChecklistsAndCache({
    required String cacheScope,
    required String serviceId,
  }) async {
    final bundle = await getServiceChecklists(serviceId: serviceId);
    await _cache.writeMap(
      _serviceChecklistCacheKey(cacheScope: cacheScope, serviceId: serviceId),
      _checklistBundleToMap(bundle),
    );

    final categoryKey = bundle.categoryCode.trim();
    final phaseKey = bundle.currentPhase.trim();
    if (categoryKey.isNotEmpty && phaseKey.isNotEmpty) {
      await _cache.writeMap(
        _templateChecklistCacheKey(
          cacheScope: cacheScope,
          categoryId: categoryKey,
          phaseId: phaseKey,
        ),
        {
          'items': bundle.templates
              .map((template) => _checklistTemplateToMap(template))
              .toList(growable: false),
        },
      );
    }
    return bundle;
  }

  Future<TechnicalVisitModel?> getTechnicalVisitByOrderAndCache({
    required String cacheScope,
    required String orderId,
  }) async {
    final visit = await getTechnicalVisitByOrder(orderId);
    if (visit == null) {
      await _cache.remove(
        _technicalVisitCacheKey(cacheScope: cacheScope, orderId: orderId),
      );
      return null;
    }
    await _cache.writeMap(
      _technicalVisitCacheKey(cacheScope: cacheScope, orderId: orderId),
      _technicalVisitToMap(visit),
    );
    return visit;
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
    String? categoryId,
    required int priority,
    required String title,
    required String description,
    String? category,
    String? addressSnapshot,
    double? quotedAmount,
    double? depositAmount,
    String? orderType,
    String? orderState,
    String? adminPhase,
    String? adminStatus,
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
          if (categoryId != null && categoryId.trim().isNotEmpty)
            'categoryId': categoryId.trim(),
          if (category != null && category.trim().isNotEmpty)
            'category': category.trim(),
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
          if (adminPhase != null && adminPhase.trim().isNotEmpty)
            'adminPhase': adminPhase.trim(),
          if (adminStatus != null && adminStatus.trim().isNotEmpty)
            'adminStatus': adminStatus.trim(),
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

  Future<ServiceModel> changeAdminStatus({
    required String serviceId,
    required String adminStatus,
    String? message,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.serviceAdminStatus(serviceId),
        data: {
          'adminStatus': adminStatus,
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

  Future<ServiceModel> changeAdminPhase({
    required String serviceId,
    required String adminPhase,
    String? message,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.serviceAdminPhase(serviceId),
        data: {
          'adminPhase': adminPhase,
          if (message != null && message.trim().isNotEmpty) 'message': message,
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
        _formatDioError(e, 'No se pudo guardar actualización'),
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
        _formatDioError(e, 'No se pudo cargar el reporte técnico'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar el reporte',
      );
    }
  }

  Future<ServiceChecklistBundleModel> getServiceChecklists({
    required String serviceId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.serviceChecklists(serviceId),
        options: Options(responseType: ResponseType.plain),
      );

      final raw = _decodeJsonMap(res.data);
      return ServiceChecklistBundleModel.fromJson(raw);
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudo cargar el checklist dinámico'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar el checklist dinámico',
      );
    }
  }

  Future<List<ServiceChecklistCategoryModel>> listChecklistCategories() async {
    try {
      final res = await _dio.get(
        ApiRoutes.checklistCategories,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = _decodeJsonList(res.data);
      return raw
          .whereType<Map>()
          .map(
            (item) => ServiceChecklistCategoryModel.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudieron cargar las categorías de checklist'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar categorías de checklist',
      );
    }
  }

  Future<List<ServiceChecklistPhaseModel>> listChecklistPhases() async {
    try {
      final res = await _dio.get(
        ApiRoutes.checklistPhases,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = _decodeJsonList(res.data);
      return raw
          .whereType<Map>()
          .map(
            (item) => ServiceChecklistPhaseModel.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudieron cargar las fases de checklist'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar fases de checklist',
      );
    }
  }

  Future<List<ServiceChecklistTemplateModel>> listChecklistTemplates({
    String? categoryId,
    String? phaseId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.checklistTemplates,
        options: Options(responseType: ResponseType.plain),
        queryParameters: {
          if (categoryId != null && categoryId.trim().isNotEmpty)
            'categoryId': categoryId.trim(),
          if (phaseId != null && phaseId.trim().isNotEmpty)
            'phaseId': phaseId.trim(),
        },
      );
      final raw = _decodeJsonList(res.data);
      return raw
          .whereType<Map>()
          .map(
            (item) => ServiceChecklistTemplateModel.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudieron cargar las plantillas de checklist'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar plantillas de checklist',
      );
    }
  }

  Future<List<ServiceChecklistTemplateModel>> listChecklistTemplatesFast({
    required String cacheScope,
    required String categoryId,
    required String phaseId,
  }) async {
    final cached = await getCachedChecklistTemplates(
      cacheScope: cacheScope,
      categoryId: categoryId,
      phaseId: phaseId,
    );
    if (cached != null && cached.isNotEmpty) {
      unawaited(
        listChecklistTemplates(
          categoryId: categoryId,
          phaseId: phaseId,
        ).then((remote) async {
          await _cache.writeMap(
            _templateChecklistCacheKey(
              cacheScope: cacheScope,
              categoryId: categoryId,
              phaseId: phaseId,
            ),
            {
              'items': remote
                  .map((template) => _checklistTemplateToMap(template))
                  .toList(growable: false),
            },
          );
        }),
      );
      return cached;
    }

    final remote = await listChecklistTemplates(
      categoryId: categoryId,
      phaseId: phaseId,
    );
    await _cache.writeMap(
      _templateChecklistCacheKey(
        cacheScope: cacheScope,
        categoryId: categoryId,
        phaseId: phaseId,
      ),
      {
        'items': remote
          .map((template) => _checklistTemplateToMap(template))
            .toList(growable: false),
      },
    );
    return remote;
  }

  Future<void> createChecklistTemplate({
    required String categoryId,
    required String phaseId,
    required ServiceChecklistSectionType type,
    String? title,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.checklistTemplate,
        data: {
          'categoryId': categoryId.trim(),
          'phaseId': phaseId.trim(),
          'type': serviceChecklistSectionTypeCode(type),
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudo crear el checklist'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> createChecklistItem({
    required String templateId,
    required String label,
    bool isRequired = true,
    int orderIndex = 0,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.checklistItem,
        data: {
          'templateId': templateId.trim(),
          'label': label.trim(),
          'isRequired': isRequired,
          'orderIndex': orderIndex,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudo agregar el item al checklist'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> checkServiceChecklistItem({
    required String itemId,
    required bool isChecked,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.checklistItemCheck(itemId),
        data: {'isChecked': isChecked},
      );
    } on DioException catch (e) {
      throw ApiException(
        _formatDioError(e, 'No se pudo actualizar el checklist'),
        e.response?.statusCode,
      );
    }
  }

  Future<bool> checkServiceChecklistItemOrQueue({
    required String scope,
    required String itemId,
    required bool isChecked,
  }) async {
    try {
      await checkServiceChecklistItem(itemId: itemId, isChecked: isChecked);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_checkChecklistSyncType:$itemId',
        type: _checkChecklistSyncType,
        scope: scope,
        payload: {'itemId': itemId, 'isChecked': isChecked},
      );
      return true;
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
        _formatDioError(e, 'No se pudo guardar el reporte técnico'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al guardar el reporte',
      );
    }
  }

  Future<bool> upsertExecutionReportOrQueue({
    required String scope,
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
      await upsertExecutionReport(
        serviceId: serviceId,
        technicianId: technicianId,
        phase: phase,
        arrivedAt: arrivedAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
        notes: notes,
        checklistData: checklistData,
        phaseSpecificData: phaseSpecificData,
        clientApproved: clientApproved,
      );
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_saveExecutionReportSyncType:$serviceId',
        type: _saveExecutionReportSyncType,
        scope: scope,
        payload: {
          'serviceId': serviceId,
          'technicianId': technicianId,
          'phase': phase,
          'arrivedAt': arrivedAt?.toIso8601String(),
          'startedAt': startedAt?.toIso8601String(),
          'finishedAt': finishedAt?.toIso8601String(),
          'notes': notes,
          'checklistData': checklistData,
          'phaseSpecificData': phaseSpecificData,
          'clientApproved': clientApproved,
        },
      );
      return true;
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
        _formatDioError(e, 'No se pudo agregar el cambio'),
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
        _formatDioError(e, 'No se pudo eliminar el cambio'),
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

  // Levantamiento Técnico (Technical Visit Report)
  Future<TechnicalVisitModel?> getTechnicalVisitByOrder(String orderId) async {
    try {
      final res = await _dio.get(
        ApiRoutes.technicalVisitByOrder(orderId),
        options: Options(responseType: ResponseType.plain),
      );
      final raw = _decodeJsonMap(res.data);
      return TechnicalVisitModel.fromJson(raw);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) return null;
      if (code == 401) {
        throw ApiException('No autorizado. Inicia sesión nuevamente.', 401);
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el levantamiento'),
        code,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al cargar el levantamiento',
      );
    }
  }

  Future<TechnicalVisitModel> createTechnicalVisit({
    required Map<String, dynamic> payload,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.technicalVisits,
        data: payload,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = _decodeJsonMap(res.data);
      return TechnicalVisitModel.fromJson(raw);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException('No autorizado. Inicia sesión nuevamente.', 401);
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el levantamiento'),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al crear el levantamiento',
      );
    }
  }

  Future<TechnicalVisitModel> updateTechnicalVisit({
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.technicalVisitDetail(id),
        data: payload,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = _decodeJsonMap(res.data);
      return TechnicalVisitModel.fromJson(raw);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw ApiException('No autorizado. Inicia sesión nuevamente.', 401);
      }
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo actualizar el levantamiento',
        ),
        e.response?.statusCode,
      );
    } on FormatException {
      throw ApiException(
        'Respuesta inválida del servidor al actualizar el levantamiento',
      );
    }
  }

  Future<bool> saveTechnicalVisitOrQueue({
    required String scope,
    required String serviceId,
    required String technicianId,
    required String? visitId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      if (visitId == null || visitId.trim().isEmpty) {
        await createTechnicalVisit(
          payload: {'order_id': serviceId, 'technician_id': technicianId, ...payload},
        );
      } else {
        await updateTechnicalVisit(id: visitId, payload: payload);
      }
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_saveTechnicalVisitSyncType:$serviceId',
        type: _saveTechnicalVisitSyncType,
        scope: scope,
        payload: {
          'visitId': visitId,
          'payload': visitId == null || visitId.trim().isEmpty
              ? {'order_id': serviceId, 'technician_id': technicianId, ...payload}
              : payload,
        },
      );
      return true;
    }
  }
}
