import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  final Dio _dio;

  SalidasTecnicasRepository(this._dio);

  static final _skipLoaderOptions = Options(extra: {'skipLoader': true});

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

  Future<List<VehiculoModel>> listVehiculos() async {
    try {
      final res = await _dio.get(
        ApiRoutes.tecnicoVehiculos,
        options: _skipLoaderOptions,
      );
      final items = (res.data as Map)['items'] as List?;
      return (items ?? const [])
          .whereType<Map>()
          .map((e) => VehiculoModel.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar vehículos'),
        e.response?.statusCode,
      );
    }
  }

  Future<VehiculoModel> createVehiculo({
    required String nombre,
    required String tipo,
    String? placa,
    required String combustibleTipo,
    double? rendimientoKmLitro,
    required bool esEmpresa,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.tecnicoVehiculos,
        options: _skipLoaderOptions,
        data: {
          'nombre': nombre,
          'tipo': tipo,
          'placa': placa,
          'combustibleTipo': combustibleTipo,
          if (rendimientoKmLitro != null)
            'rendimientoKmLitro': rendimientoKmLitro,
          'esEmpresa': esEmpresa,
        },
      );
      return VehiculoModel.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear vehículo'),
        e.response?.statusCode,
      );
    }
  }

  Future<SalidaTecnicaModel?> getSalidaAbierta() async {
    try {
      final res = await _dio.get(
        ApiRoutes.tecnicoSalidasAbierta,
        options: _skipLoaderOptions,
      );
      final salida = (res.data as Map)['salida'];
      if (salida is Map) {
        return SalidaTecnicaModel.fromJson(salida.cast<String, dynamic>());
      }
      return null;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar salida abierta'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<SalidaTecnicaModel>> listHistorial({
    String? from,
    String? to,
    String? estado,
  }) async {
    try {
      if (!kIsWeb) {
        final sw = Stopwatch()..start();
        final resPlain = await _dio.get(
          ApiRoutes.tecnicoSalidasHistorial,
          options: Options(
            responseType: ResponseType.plain,
            extra: const {'skipLoader': true},
          ),
          queryParameters: {
            if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
            if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
            if (estado != null && estado.trim().isNotEmpty)
              'estado': estado.trim(),
          },
        );
        final body = resPlain.data;
        final text = body is String ? body : body.toString();
        debugPrint(
          '[SalidasTecnicasRepository] Historial (plain) recibido en ${sw.elapsedMilliseconds}ms (chars=${text.length})',
        );
        List<Map<String, dynamic>> normalized;
        try {
          normalized = await compute(_extractSalidaTecnicaItemsFromJson, text);
        } catch (e, st) {
          debugPrint(
            '[SalidasTecnicasRepository] Error parseando historial en isolate: $e',
          );
          debugPrintStack(stackTrace: st);
          throw ApiException('No se pudo cargar historial');
        }
        return _mapSalidaTecnicaModelsYielding(normalized);
      }

      final res = await _dio.get(
        ApiRoutes.tecnicoSalidasHistorial,
        options: _skipLoaderOptions,
        queryParameters: {
          if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
          if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
          if (estado != null && estado.trim().isNotEmpty)
            'estado': estado.trim(),
        },
      );
      final items = (res.data as Map)['items'] as List?;

      final normalized = (items ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);

      // Si el historial es grande, parsearlo en el hilo UI puede “congelar” la app.
      // En mobile/desktop usamos isolate con compute; en web parseamos inline.
      return _mapSalidaTecnicaModelsYielding(normalized);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar historial'),
        e.response?.statusCode,
      );
    }
  }

  Future<SalidaTecnicaModel> iniciar({
    required String servicioId,
    required String vehiculoId,
    required bool esVehiculoPropio,
    required double latSalida,
    required double lngSalida,
    String? observacion,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.tecnicoSalidasIniciar,
        options: _skipLoaderOptions,
        data: {
          'servicioId': servicioId,
          'vehiculoId': vehiculoId,
          'esVehiculoPropio': esVehiculoPropio,
          'latSalida': latSalida,
          'lngSalida': lngSalida,
          'observacion': observacion,
        },
      );
      return SalidaTecnicaModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo iniciar la salida'),
        e.response?.statusCode,
      );
    }
  }

  Future<SalidaTecnicaModel> marcarLlegada({
    required String salidaId,
    required double latLlegada,
    required double lngLlegada,
    String? observacion,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.tecnicoSalidasLlegada(salidaId),
        options: _skipLoaderOptions,
        data: {
          'latLlegada': latLlegada,
          'lngLlegada': lngLlegada,
          'observacion': observacion,
        },
      );
      return SalidaTecnicaModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo marcar llegada'),
        e.response?.statusCode,
      );
    }
  }

  Future<SalidaTecnicaModel> finalizar({
    required String salidaId,
    required double latFinal,
    required double lngFinal,
    String? observacion,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.tecnicoSalidasFinalizar(salidaId),
        options: _skipLoaderOptions,
        data: {
          'latFinal': latFinal,
          'lngFinal': lngFinal,
          'observacion': observacion,
        },
      );
      return SalidaTecnicaModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo finalizar la salida'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<AdminSalidaTecnicaModel>> adminListSalidas({
    String? from,
    String? to,
    String? estado,
    String? tecnicoId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.adminSalidasTecnicas,
        queryParameters: {
          if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
          if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
          if (estado != null && estado.trim().isNotEmpty)
            'estado': estado.trim(),
          if (tecnicoId != null && tecnicoId.trim().isNotEmpty)
            'tecnicoId': tecnicoId.trim(),
        },
      );

      final items = (res.data as Map)['items'] as List?;

      final normalized = (items ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);

      if (kIsWeb) {
        return normalized
            .map(AdminSalidaTecnicaModel.fromJson)
            .toList(growable: false);
      }
      return compute(_parseAdminSalidaTecnicaList, normalized);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar salidas'),
        e.response?.statusCode,
      );
    }
  }

  // compute() requiere funciones top-level o static.
  static List<Map<String, dynamic>> _extractSalidaTecnicaItemsFromJson(
    String body,
  ) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return const <Map<String, dynamic>>[];
    final items = decoded['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  static Future<List<SalidaTecnicaModel>> _mapSalidaTecnicaModelsYielding(
    List<Map<String, dynamic>> items,
  ) async {
    // Nota: en Web y/o con historiales grandes, un map() masivo puede dejar la
    // UI sin responder. Procesamos en lotes y cedemos el event-loop.
    final out = <SalidaTecnicaModel>[];
    final total = items.length;
    for (var i = 0; i < total; i++) {
      out.add(SalidaTecnicaModel.fromJson(items[i]));
      if (i > 0 && (i % 200 == 0)) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
  }

  static List<AdminSalidaTecnicaModel> _parseAdminSalidaTecnicaList(
    List<Map<String, dynamic>> items,
  ) {
    return items.map(AdminSalidaTecnicaModel.fromJson).toList(growable: false);
  }

  Future<void> adminAprobarSalida({
    required String salidaId,
    String? observacion,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.adminSalidaAprobar(salidaId),
        data: {if (observacion != null) 'observacion': observacion},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo aprobar la salida'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> adminRechazarSalida({
    required String salidaId,
    required String observacion,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.adminSalidaRechazar(salidaId),
        data: {'observacion': observacion},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo rechazar la salida'),
        e.response?.statusCode,
      );
    }
  }
}
