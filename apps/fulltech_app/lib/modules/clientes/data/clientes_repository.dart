import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../cliente_model.dart';

enum ClientesOrder { az, za }
enum CorreoFilter { todos, conCorreo, sinCorreo }
enum EstadoFilter { activos, eliminados, todos }

final clientesRepositoryProvider = Provider<ClientesRepository>((ref) {
  return ClientesRepository(ref.watch(dioProvider));
});

class ClientesRepository {
  final Dio _dio;

  ClientesRepository(this._dio);

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
          .map((cliente) => cliente.ownerId.isEmpty
              ? cliente.copyWith(ownerId: ownerId)
              : cliente)
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
      final cliente = ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
      return cliente.ownerId.isEmpty ? cliente.copyWith(ownerId: ownerId) : cliente;
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
      if (cliente.id.isEmpty) {
        final res = await _dio.post(ApiRoutes.clients, data: payload);
        final created = ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
        return created.ownerId.isEmpty ? created.copyWith(ownerId: ownerId) : created;
      }

      final res = await _dio.patch(ApiRoutes.clientDetail(cliente.id), data: payload);
      final updated = ClienteModel.fromJson((res.data as Map).cast<String, dynamic>());
      return updated.ownerId.isEmpty ? updated.copyWith(ownerId: ownerId) : updated;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el cliente'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> softDeleteClient({required String ownerId, required String id}) async {
    try {
      await _dio.delete(ApiRoutes.clientDetail(id), data: {'owner_id': ownerId});
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
