import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/offline/sync_queue_service.dart';
import '../cotizacion_models.dart';
import 'cotizaciones_local_repository.dart';

final cotizacionesRepositoryProvider = Provider<CotizacionesRepository>((ref) {
  final repository = CotizacionesRepository(
    ref.watch(dioProvider),
    ref.read(cotizacionesLocalRepositoryProvider),
    ref.read(syncQueueServiceProvider.notifier),
  );
  repository.registerSyncHandlers();
  return repository;
});

class CotizacionesRepository {
  final Dio _dio;
  final CotizacionesLocalRepository _local;
  final SyncQueueService _syncQueue;

  static const String _createSyncType = 'quotes.create';
  static const String _updateSyncType = 'quotes.update';
  static const String _deleteSyncType = 'quotes.delete';

  bool _handlersRegistered = false;

  CotizacionesRepository(this._dio, this._local, this._syncQueue);

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;

    _syncQueue.registerHandler(_createSyncType, (payload) async {
      final localId = (payload['localId'] ?? '').toString();
      final draft = CotizacionModel.fromMap(
        ((payload['quote'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      );
      final remote = await create(draft.copyWith(id: ''));
      await _local.deleteById(localId);
      await _local.upsert(remote);
    });

    _syncQueue.registerHandler(_updateSyncType, (payload) async {
      final id = (payload['id'] ?? '').toString();
      final draft = CotizacionModel.fromMap(
        ((payload['quote'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      );
      final remote = await update(id, draft);
      await _local.upsert(remote);
    });

    _syncQueue.registerHandler(_deleteSyncType, (payload) async {
      final id = (payload['id'] ?? '').toString();
      await deleteById(id);
    });
  }

  bool _shouldQueueSync(ApiException error) {
    final code = error.code;
    return code == null || code >= 500;
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return fallback;
  }

  Future<List<CotizacionModel>> list({
    String? customerPhone,
    int take = 80,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.cotizaciones,
        queryParameters: {
          if (customerPhone != null && customerPhone.trim().isNotEmpty)
            'customerPhone': customerPhone.trim(),
          'take': take,
        },
      );

      final data = res.data;
      if (data is Map && data['items'] is List) {
        final rows = (data['items'] as List).whereType<Map>();
        return rows
            .map((row) => CotizacionModel.fromApi(row.cast<String, dynamic>()))
            .toList();
      }

      if (data is List) {
        final rows = data.whereType<Map>();
        return rows
            .map((row) => CotizacionModel.fromApi(row.cast<String, dynamic>()))
            .toList();
      }

      return const [];
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar cotizaciones'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<CotizacionModel>> getCachedList({
    String? customerPhone,
    int take = 80,
  }) async {
    final items = await _local.listAll();
    final phone = (customerPhone ?? '').trim();
    final filtered = phone.isEmpty
        ? items
        : items.where((item) => (item.customerPhone ?? '').trim() == phone).toList(growable: false);
    return filtered.take(take).toList(growable: false);
  }

  Future<List<CotizacionModel>> listAndCache({
    String? customerPhone,
    int take = 80,
  }) async {
    final items = await list(customerPhone: customerPhone, take: take);
    for (final item in items) {
      await _local.upsert(item);
    }
    return items;
  }

  Future<CotizacionModel?> getCachedById(String id) async {
    final items = await _local.listAll();
    for (final item in items) {
      if (item.id.trim() == id.trim()) return item;
    }
    return null;
  }

  Future<CotizacionModel> create(CotizacionModel draft) async {
    try {
      final res = await _dio.post(
        ApiRoutes.cotizaciones,
        data: draft.toCreateDto(),
      );
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<CotizacionModel> getById(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.cotizacionDetail(id));
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<CotizacionModel> getByIdAndCache(String id) async {
    final item = await getById(id);
    await _local.upsert(item);
    return item;
  }

  Future<CotizacionModel> update(String id, CotizacionModel draft) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.cotizacionDetail(id),
        data: draft.toCreateDto(),
      );
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo actualizar la cotización',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteById(String id) async {
    try {
      await _dio.delete(ApiRoutes.cotizacionDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<bool> createOrQueue(CotizacionModel draft) async {
    final localId = draft.id.trim().isEmpty
        ? 'local_quote_${DateTime.now().microsecondsSinceEpoch}'
        : draft.id;
    final optimistic = draft.copyWith(id: localId);
    await _local.upsert(optimistic);
    try {
      final remote = await create(draft);
      await _local.deleteById(localId);
      await _local.upsert(remote);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_createSyncType:$localId',
        type: _createSyncType,
        scope: 'quotes',
        payload: {'localId': localId, 'quote': optimistic.toMap()},
      );
      return true;
    }
  }

  Future<bool> updateOrQueue(String id, CotizacionModel draft) async {
    final optimistic = draft.copyWith(id: id);
    await _local.upsert(optimistic);
    try {
      final remote = await update(id, draft);
      await _local.upsert(remote);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_updateSyncType:$id',
        type: _updateSyncType,
        scope: 'quotes',
        payload: {'id': id, 'quote': optimistic.toMap()},
      );
      return true;
    }
  }

  Future<bool> deleteOrQueue(String id) async {
    await _local.deleteById(id);
    try {
      await deleteById(id);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_deleteSyncType:$id',
        type: _deleteSyncType,
        scope: 'quotes',
        payload: {'id': id},
      );
      return true;
    }
  }
}
