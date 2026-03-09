import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../salidas_tecnicas_models.dart';

final salidasTecnicasRepositoryProvider = Provider<SalidasTecnicasRepository>((
  ref,
) {
  return SalidasTecnicasRepository(ref.watch(dioProvider));
});

class SalidasTecnicasRepository {
  SalidasTecnicasRepository(this._dio);

  final Dio _dio;

  Future<List<TechVehicle>> listVehicles() async {
    final map = await _getMap(ApiRoutes.tecnicoVehiculos);
    final items = (map['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((row) => TechVehicle.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<TechVehicle> createVehicle(Map<String, dynamic> payload) async {
    final map = await _postMap(ApiRoutes.tecnicoVehiculos, payload);
    return TechVehicle.fromJson(map);
  }

  Future<TechVehicle> updateVehicle(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final map = await _patchMap('${ApiRoutes.tecnicoVehiculos}/$id', payload);
    return TechVehicle.fromJson(map);
  }

  Future<TechnicalDeparture?> getOpenDeparture() async {
    final map = await _getMap(ApiRoutes.tecnicoSalidaAbierta);
    final raw = map['salida'];
    if (raw is Map<String, dynamic>) {
      return TechnicalDeparture.fromJson(raw);
    }
    if (raw is Map) {
      return TechnicalDeparture.fromJson(raw.cast<String, dynamic>());
    }
    return null;
  }

  Future<List<TechnicalDeparture>> listHistory() async {
    final map = await _getMap(ApiRoutes.tecnicoSalidasHistorial);
    final items = (map['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((row) => TechnicalDeparture.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<TechnicalDeparture>> listAdminDepartures({
    String? tecnicoId,
    String? estado,
  }) async {
    final map = await _getMap(
      ApiRoutes.adminSalidasTecnicas,
      queryParameters: {
        if (tecnicoId != null && tecnicoId.trim().isNotEmpty)
          'tecnicoId': tecnicoId.trim(),
        if (estado != null && estado.trim().isNotEmpty) 'estado': estado.trim(),
      },
    );
    final items = (map['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((row) => TechnicalDeparture.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<TechnicalDeparture> approveDeparture(
    String id, {
    String? observacion,
  }) async {
    final map = await _postMap(ApiRoutes.adminSalidaAprobar(id), {
      if (observacion != null && observacion.trim().isNotEmpty)
        'observacion': observacion.trim(),
    });
    return TechnicalDeparture.fromJson(map);
  }

  Future<TechnicalDeparture> rejectDeparture(
    String id, {
    required String observacion,
  }) async {
    final map = await _postMap(ApiRoutes.adminSalidaRechazar(id), {
      'observacion': observacion.trim(),
    });
    return TechnicalDeparture.fromJson(map);
  }

  Future<List<TechFuelPayment>> listAdminFuelPayments({
    String? tecnicoId,
  }) async {
    final map = await _getMap(
      ApiRoutes.adminPagosCombustibleTecnicos,
      queryParameters: {
        if (tecnicoId != null && tecnicoId.trim().isNotEmpty)
          'tecnicoId': tecnicoId.trim(),
      },
    );
    final items = (map['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((row) => TechFuelPayment.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<TechFuelPayment> createFuelPaymentPeriod({
    required String tecnicoId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    final map = await _postMap(ApiRoutes.adminPagosCombustibleTecnicos, {
      'tecnicoId': tecnicoId,
      'fechaInicio': fechaInicio.toIso8601String(),
      'fechaFin': fechaFin.toIso8601String(),
    });
    final pago = map['pago'];
    if (pago is Map<String, dynamic>) {
      return TechFuelPayment.fromJson(pago);
    }
    if (pago is Map) {
      return TechFuelPayment.fromJson(pago.cast<String, dynamic>());
    }
    throw ApiException('Respuesta inválida al crear pago de combustible');
  }

  Future<Map<String, dynamic>> markFuelPaymentPaid(
    String id, {
    DateTime? fechaPago,
  }) async {
    return _postMap(ApiRoutes.adminPagoCombustiblePagado(id), {
      if (fechaPago != null) 'fechaPago': fechaPago.toIso8601String(),
    });
  }

  Future<TechnicalDeparture> startDeparture({
    required String servicioId,
    required String vehiculoId,
    required bool esVehiculoPropio,
    required double latSalida,
    required double lngSalida,
    String? observacion,
  }) async {
    final map = await _postMap(ApiRoutes.tecnicoSalidasIniciar, {
      'servicioId': servicioId,
      'vehiculoId': vehiculoId,
      'esVehiculoPropio': esVehiculoPropio,
      'latSalida': latSalida,
      'lngSalida': lngSalida,
      if (observacion != null && observacion.trim().isNotEmpty)
        'observacion': observacion.trim(),
    });
    return TechnicalDeparture.fromJson(map);
  }

  Future<TechnicalDeparture> markArrival({
    required String salidaId,
    required double latLlegada,
    required double lngLlegada,
    String? observacion,
  }) async {
    final map = await _patchMap(ApiRoutes.tecnicoSalidaLlegada(salidaId), {
      'latLlegada': latLlegada,
      'lngLlegada': lngLlegada,
      if (observacion != null && observacion.trim().isNotEmpty)
        'observacion': observacion.trim(),
    });
    return TechnicalDeparture.fromJson(map);
  }

  Future<TechnicalDeparture> finishDeparture({
    required String salidaId,
    required double latFinal,
    required double lngFinal,
    String? observacion,
  }) async {
    final map = await _patchMap(ApiRoutes.tecnicoSalidaFinalizar(salidaId), {
      'latFinal': latFinal,
      'lngFinal': lngFinal,
      if (observacion != null && observacion.trim().isNotEmpty)
        'observacion': observacion.trim(),
    });
    return TechnicalDeparture.fromJson(map);
  }

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParameters);
      return _castMap(response.data);
    } on DioException catch (e) {
      throw ApiException(_messageFrom(e, 'No se pudo cargar salidas técnicas'));
    }
  }

  Future<Map<String, dynamic>> _postMap(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(path, data: data);
      return _castMap(response.data);
    } on DioException catch (e) {
      throw ApiException(_messageFrom(e, 'No se pudo guardar la información'));
    }
  }

  Future<Map<String, dynamic>> _patchMap(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.patch(path, data: data);
      return _castMap(response.data);
    } on DioException catch (e) {
      throw ApiException(
        _messageFrom(e, 'No se pudo actualizar la información'),
      );
    }
  }

  Map<String, dynamic> _castMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    throw ApiException('Respuesta inválida del servidor');
  }

  String _messageFrom(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) {
          return first;
        }
      }
    }
    return fallback;
  }
}
