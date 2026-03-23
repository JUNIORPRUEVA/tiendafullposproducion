import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/offline/sync_queue_service.dart';
import '../../../core/errors/api_exception.dart';
import '../cliente_model.dart';
import '../cliente_profile_model.dart';
import '../cliente_timeline_model.dart';

enum ClientesOrder { az, za }

enum CorreoFilter { todos, conCorreo, sinCorreo }

enum EstadoFilter { activos, eliminados, todos }

final clientesRepositoryProvider = Provider<ClientesRepository>((ref) {
  final repository = ClientesRepository(
    ref.watch(dioProvider),
    ref.read(syncQueueServiceProvider.notifier),
  );
  repository.registerSyncHandlers();
  return repository;
});

class ClientesRepository {
  final Dio _dio;
  final SyncQueueService _syncQueue;
  final LocalJsonCache _cache = LocalJsonCache();

  static const String _upsertSyncType = 'clientes.upsert';
  static const String _deleteSyncType = 'clientes.delete';
  static const Duration _cacheTtl = Duration(days: 7);

  bool _handlersRegistered = false;

  ClientesRepository(this._dio, this._syncQueue);

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;

    _syncQueue.registerHandler(_upsertSyncType, (payload) async {
      final ownerId = (payload['ownerId'] ?? '').toString();
      final cliente = ClienteModel.fromJson(
        ((payload['cliente'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      );
      await upsertClient(
        ownerId: ownerId,
        cliente: cliente.copyWith(updatedLocal: false, syncStatus: 'synced'),
      );
    });

    _syncQueue.registerHandler(_deleteSyncType, (payload) async {
      final ownerId = (payload['ownerId'] ?? '').toString();
      final id = (payload['id'] ?? '').toString();
      await softDeleteClient(ownerId: ownerId, id: id);
    });
  }

  String _cacheKey({
    required String ownerId,
    required String search,
    required ClientesOrder order,
    required CorreoFilter correoFilter,
    required EstadoFilter estadoFilter,
  }) {
    return [
      'clientes',
      ownerId.trim(),
      search.trim().toLowerCase(),
      order.name,
      correoFilter.name,
      estadoFilter.name,
    ].join('|');
  }

  bool _shouldQueueSync(ApiException error) {
    final code = error.code;
    return code == null || code >= 500;
  }

  Future<List<ClienteModel>> getCachedClients({
    required String ownerId,
    String search = '',
    ClientesOrder order = ClientesOrder.az,
    CorreoFilter correoFilter = CorreoFilter.todos,
    EstadoFilter estadoFilter = EstadoFilter.activos,
  }) async {
    final cache = await _cache.readMap(
      _cacheKey(
        ownerId: ownerId,
        search: search,
        order: order,
        correoFilter: correoFilter,
        estadoFilter: estadoFilter,
      ),
      maxAge: _cacheTtl,
    );
    final rows = cache?['items'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => ClienteModel.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> saveClientsSnapshot({
    required String ownerId,
    required String search,
    required ClientesOrder order,
    required CorreoFilter correoFilter,
    required EstadoFilter estadoFilter,
    required List<ClienteModel> items,
  }) async {
    await _cache.writeMap(
      _cacheKey(
        ownerId: ownerId,
        search: search,
        order: order,
        correoFilter: correoFilter,
        estadoFilter: estadoFilter,
      ),
      {'items': items.map((item) => item.toJson()).toList(growable: false)},
    );
  }

  Future<List<ClienteModel>> listClientsAndCache({
    required String ownerId,
    String search = '',
    ClientesOrder order = ClientesOrder.az,
    CorreoFilter correoFilter = CorreoFilter.todos,
    EstadoFilter estadoFilter = EstadoFilter.activos,
    int page = 1,
    int pageSize = 100,
  }) async {
    final items = await listClients(
      ownerId: ownerId,
      search: search,
      order: order,
      correoFilter: correoFilter,
      estadoFilter: estadoFilter,
      page: page,
      pageSize: pageSize,
    );
    await saveClientsSnapshot(
      ownerId: ownerId,
      search: search,
      order: order,
      correoFilter: correoFilter,
      estadoFilter: estadoFilter,
      items: items,
    );
    return items;
  }

  Future<ClienteModel> syncUpsertClientOrQueue({
    required String ownerId,
    required ClienteModel cliente,
  }) async {
    try {
      final synced = await upsertClient(ownerId: ownerId, cliente: cliente);
      return synced.copyWith(syncStatus: 'synced', updatedLocal: false);
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_upsertSyncType:${cliente.id}',
        type: _upsertSyncType,
        scope: ownerId,
        payload: {'ownerId': ownerId, 'cliente': cliente.toJson()},
      );
      return cliente.copyWith(syncStatus: 'pending', updatedLocal: true);
    }
  }

  Future<void> syncDeleteClientOrQueue({
    required String ownerId,
    required String id,
  }) async {
    try {
      await softDeleteClient(ownerId: ownerId, id: id);
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_deleteSyncType:$id',
        type: _deleteSyncType,
        scope: ownerId,
        payload: {'ownerId': ownerId, 'id': id},
      );
    }
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

  bool _isLocalId(String id) {
    final trimmed = id.trim();
    return trimmed.isEmpty || trimmed.startsWith('local_');
  }

  Future<List<ClienteModel>> listClients({
    required String ownerId,
    String search = '',
    ClientesOrder order = ClientesOrder.az,
    CorreoFilter correoFilter = CorreoFilter.todos,
    EstadoFilter estadoFilter = EstadoFilter.activos,
    int page = 1,
    int pageSize = 100,
  }) async {
    try {
      final safePage = page < 1 ? 1 : page;
      final safePageSize = pageSize < 1 ? 20 : pageSize;
      final includeDeleted = estadoFilter == EstadoFilter.todos ? true : null;
      final onlyDeleted = estadoFilter == EstadoFilter.eliminados ? true : null;

      final res = await _dio.get(
        ApiRoutes.clients,
        queryParameters: {
          if (search.trim().isNotEmpty) 'search': search.trim(),
          'page': safePage,
          'pageSize': safePageSize,
          if (includeDeleted != null) 'includeDeleted': includeDeleted,
          if (onlyDeleted != null) 'onlyDeleted': onlyDeleted,
        },
      );

      final raw = res.data;
      final List<dynamic> rows;
      if (raw is List) {
        rows = raw;
      } else if (raw is Map && raw['items'] is List) {
        rows = (raw['items'] as List<dynamic>);
      } else {
        rows = const [];
      }

      final mapped = rows
          .whereType<Map>()
          .map((e) => ClienteModel.fromJson(e.cast<String, dynamic>()))
          .map(
            (cliente) => cliente.ownerId.isEmpty
                ? cliente.copyWith(ownerId: ownerId)
                : cliente,
          )
          .toList();

      final filteredByEstado = mapped.where((cliente) {
        switch (estadoFilter) {
          case EstadoFilter.activos:
            return !cliente.isDeleted;
          case EstadoFilter.eliminados:
            return cliente.isDeleted;
          case EstadoFilter.todos:
            return true;
        }
      });

      final filteredByCorreo = filteredByEstado.where((cliente) {
        final hasCorreo = (cliente.correo ?? '').trim().isNotEmpty;
        switch (correoFilter) {
          case CorreoFilter.todos:
            return true;
          case CorreoFilter.conCorreo:
            return hasCorreo;
          case CorreoFilter.sinCorreo:
            return !hasCorreo;
        }
      }).toList();

      filteredByCorreo.sort((a, b) {
        final left = a.nombre.toLowerCase();
        final right = b.nombre.toLowerCase();
        return order == ClientesOrder.az
            ? left.compareTo(right)
            : right.compareTo(left);
      });

      return filteredByCorreo;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar los clientes'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClienteModel> getClientById({
    required String ownerId,
    required String id,
  }) async {
    try {
      final res = await _dio.get(ApiRoutes.clientDetail(id));
      final cliente = ClienteModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      return cliente.ownerId.isEmpty
          ? cliente.copyWith(ownerId: ownerId)
          : cliente;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClienteModel> upsertClient({
    required String ownerId,
    required ClienteModel cliente,
  }) async {
    final payload = cliente.copyWith(ownerId: ownerId).toApiPayload()
      ..removeWhere((key, value) => value == null);

    try {
      if (_isLocalId(cliente.id)) {
        final res = await _dio.post(ApiRoutes.clients, data: payload);
        final created = ClienteModel.fromJson(
          (res.data as Map).cast<String, dynamic>(),
        );
        return created.ownerId.isEmpty
            ? created.copyWith(ownerId: ownerId)
            : created;
      }

      final res = await _dio.patch(
        ApiRoutes.clientDetail(cliente.id),
        data: payload,
      );
      final updated = ClienteModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
      return updated.ownerId.isEmpty
          ? updated.copyWith(ownerId: ownerId)
          : updated;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClienteProfileResponse> getClientProfile({required String id}) async {
    try {
      final res = await _dio.get(ApiRoutes.clientProfile(id));
      final raw = res.data;
      if (raw is! Map) {
        throw ApiException('Respuesta inválida del servidor');
      }
      return ClienteProfileResponse.fromJson(raw.cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el expediente'),
        e.response?.statusCode,
      );
    }
  }

  Future<ClienteTimelineResponse> getClientTimeline({
    required String id,
    int take = 100,
    DateTime? before,
    List<String> types = const [],
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.clientTimeline(id),
        queryParameters: {
          'take': take,
          if (before != null) 'before': before.toIso8601String(),
          if (types.isNotEmpty) 'types': types.join(','),
        },
      );
      final raw = res.data;
      if (raw is! Map) {
        throw ApiException('Respuesta inválida del servidor');
      }
      return ClienteTimelineResponse.fromJson(raw.cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el historial'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> softDeleteClient({
    required String ownerId,
    required String id,
  }) async {
    if (_isLocalId(id)) {
      return;
    }
    try {
      await _dio.delete(
        ApiRoutes.clientDetail(id),
        data: {'owner_id': ownerId},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<bool> existsPhoneDuplicate({
    required String ownerId,
    required String telefono,
    String? excludingId,
  }) async {
    final normalizedPhone = _normalizePhone(telefono);
    if (normalizedPhone.isEmpty) return false;

    final clients = await listClients(
      ownerId: ownerId,
      search: telefono,
      estadoFilter: EstadoFilter.todos,
      pageSize: 200,
    );

    return clients.any((c) {
      final isSame = _normalizePhone(c.telefono) == normalizedPhone;
      final isDifferentId = excludingId == null || c.id != excludingId;
      return isSame && isDifferentId && !c.isDeleted;
    });
  }

  String _normalizePhone(String input) {
    final trimmed = input.trim();
    return trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
  }
}
