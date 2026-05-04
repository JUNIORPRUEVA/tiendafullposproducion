import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_mapper.dart';
import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import 'marketing_models.dart';

final marketingApiProvider = Provider<MarketingApi>((ref) {
  return MarketingApi(ref.watch(dioProvider));
});

class MarketingApi {
  MarketingApi(this._dio);

  final Dio _dio;
  static final _backgroundOptions = Options(extra: {'skipLoader': true});

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<MarketingDashboard> loadDashboard(DateTime date) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingDashboard,
        queryParameters: {'date': _dateOnly(date)},
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingDashboard.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar el dashboard de Publicidad');
    }
  }

  Future<MarketingFlowConfig> loadConfig() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingConfig,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingFlowConfig.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la configuracion de Publicidad');
    }
  }

  Future<List<MarketingStory>> loadStories(DateTime date) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingStories,
        queryParameters: {'date': _dateOnly(date)},
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map((item) => MarketingStory.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron cargar los estados diarios');
    }
  }

  Future<MarketingHistoryResponse> loadHistory({
    required DateTime from,
    required DateTime to,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingHistory,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          'page': page,
          'limit': limit,
        },
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingHistoryResponse.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar el historial');
    }
  }

  Future<void> generateMissing(DateTime date) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoriesGenerateMissing,
        data: {'date': _dateOnly(date)},
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron generar los contenidos faltantes');
    }
  }

  Future<void> approve(String storyId) async {
    try {
      await _dio.post(ApiRoutes.marketingStoryApprove(storyId));
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo aprobar el contenido');
    }
  }

  Future<void> reject(String storyId, {String reason = ''}) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoryReject(storyId),
        data: {'reason': reason.trim()},
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo rechazar el contenido');
    }
  }

  Future<void> regenerate(String storyId) async {
    try {
      await _dio.post(ApiRoutes.marketingStoryRegenerate(storyId));
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo regenerar el contenido');
    }
  }

  Future<void> editStory(
    String storyId, {
    required String title,
    required String shortText,
    required String longText,
    required List<String> hashtags,
    required String imagePrompt,
    required String imageUrl,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingStoryEdit(storyId),
        data: {
          'title': title.trim(),
          'shortText': shortText.trim(),
          'longText': longText.trim(),
          'hashtags': hashtags,
          'imagePrompt': imagePrompt.trim(),
          'imageUrl': imageUrl.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo editar el contenido');
    }
  }

  Future<void> updateConfig({
    required bool flujoActivo,
    required bool pausado,
    required int cantidadEstadosDiarios,
    required String horaGeneracion,
    required bool autoRegenerarSiNoAprueba,
    required int horasParaRegenerar,
    required List<String> productosPrioritarios,
    required String ciudadObjetivo,
    required String tonoDeMarca,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingConfig,
        data: {
          'flujo_activo': flujoActivo,
          'pausado': pausado,
          'cantidad_estados_diarios': cantidadEstadosDiarios,
          'hora_generacion': horaGeneracion.trim(),
          'auto_regenerar_si_no_aprueba': autoRegenerarSiNoAprueba,
          'horas_para_regenerar': horasParaRegenerar,
          'productos_prioritarios': productosPrioritarios,
          'ciudad_objetivo': ciudadObjetivo.trim(),
          'tono_de_marca': tonoDeMarca.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo guardar la configuracion');
    }
  }

  Future<void> activateFlow() async {
    try {
      await _dio.post(ApiRoutes.marketingFlowActivate);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo activar el flujo');
    }
  }

  Future<void> pauseFlow() async {
    try {
      await _dio.post(ApiRoutes.marketingFlowPause);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo pausar el flujo');
    }
  }

  Future<void> resetFlow() async {
    try {
      await _dio.post(ApiRoutes.marketingFlowReset);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo reiniciar el flujo');
    }
  }
}
