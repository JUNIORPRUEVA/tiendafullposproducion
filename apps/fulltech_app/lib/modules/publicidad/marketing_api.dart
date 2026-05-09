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
    int limit = 20,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit < 1 ? 1 : (limit > 100 ? 100 : limit);

    try {
      final res = await _dio.get(
        ApiRoutes.marketingHistory,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          'page': safePage,
          'limit': safeLimit,
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

  Future<void> generateMissing(
    DateTime date, {
    List<String> selectedMediaAssetIds = const [],
  }) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoriesGenerateMissing,
        data: {
          'date': _dateOnly(date),
          if (selectedMediaAssetIds.isNotEmpty)
            'selected_media_asset_ids': selectedMediaAssetIds,
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron generar los contenidos faltantes');
    }
  }

  Future<MarketingRepairIncompleteSummary> repairIncomplete(DateTime date) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingStoriesRepairIncomplete,
        data: {'date': _dateOnly(date)},
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingRepairIncompleteSummary.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron reparar los anuncios incompletos');
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

  Future<void> regenerateImage(String storyId, {String? customPrompt}) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoryRegenerateImage(storyId),
        data: {
          if ((customPrompt ?? '').trim().isNotEmpty)
            'reason': customPrompt!.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo regenerar la imagen');
    }
  }

  Future<void> changeBaseImage(String storyId, String mediaAssetId) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingStoryChangeBaseImage(storyId, mediaAssetId),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cambiar la imagen base');
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

  Future<MarketingResetCleanSummary> resetClean({
    bool includeResearch = false,
    bool includeDraftMedia = true,
    bool includeGeneratedImages = true,
    bool includeApprovedStories = false,
    DateTime? date,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingResetClean,
        data: {
          'includeResearch': includeResearch,
          'includeDraftMedia': includeDraftMedia,
          'includeGeneratedImages': includeGeneratedImages,
          'includeApprovedStories': includeApprovedStories,
          if (date != null) 'date': _dateOnly(date),
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingResetCleanSummary.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo ejecutar el reset limpio de Publicidad');
    }
  }

  Future<List<MarketingMediaAsset>> loadMediaAssets({
    String? category,
    String? relatedService,
    bool activeOnly = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingMediaAssets,
        options: _backgroundOptions,
        queryParameters: {
          if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
          if ((relatedService ?? '').trim().isNotEmpty)
            'related_service': relatedService!.trim(),
          if (activeOnly) 'active_only': true,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) => MarketingMediaAsset.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la galería publicitaria');
    }
  }

  /// Analyzes multiple media assets and returns AI recommendations ranked by suitability
  Future<Map<String, dynamic>> analyzeMediaAssets({
    required List<String> mediaAssetIds,
    required String storyType,
  }) async {
    try {
      final res = await _dio.post(
        '${ApiRoutes.marketingBase}/media-assets/analyze',
        data: {
          'mediaAssetIds': mediaAssetIds,
          'storyType': storyType,
        },
        options: _backgroundOptions,
      );
      return (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron analizar las imágenes disponibles');
    }
  }

  Future<MarketingMediaAsset> createMediaAsset({
    required String fileUrl,
    required String fileName,
    required String mimeType,
    required String category,
    String? relatedService,
    List<String> tags = const [],
    String? description,
    bool isActive = true,
    bool isFeatured = false,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingMediaAssets,
        data: {
          'file_url': fileUrl.trim(),
          'file_name': fileName.trim(),
          'mime_type': mimeType.trim(),
          'category': category.trim(),
          'related_service': relatedService?.trim(),
          'tags': tags,
          'description': description?.trim(),
          'is_active': isActive,
          'is_featured': isFeatured,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if ('${raw['id'] ?? ''}'.trim().isNotEmpty) {
        return MarketingMediaAsset.fromJson(raw);
      }
      throw StateError('Respuesta inválida al crear asset de galería');
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo crear el asset de galería');
    }
  }

  Future<void> updateMediaAsset(
    String id, {
    String? category,
    String? relatedService,
    List<String>? tags,
    String? description,
    bool? isActive,
    bool? isFeatured,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingMediaAssetById(id),
        data: {
          if (category != null) 'category': category.trim(),
          if (relatedService != null) 'related_service': relatedService.trim(),
          if (tags != null) 'tags': tags,
          if (description != null) 'description': description.trim(),
          if (isActive != null) 'is_active': isActive,
          if (isFeatured != null) 'is_featured': isFeatured,
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo actualizar el asset');
    }
  }

  Future<void> deleteMediaAsset(String id) async {
    try {
      await _dio.delete(ApiRoutes.marketingMediaAssetById(id));
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo eliminar el asset');
    }
  }

  Future<MarketingResearchDetail?> loadLatestResearch() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingResearchLatest,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if ('${raw['id'] ?? ''}'.trim().isEmpty) return null;
      return MarketingResearchDetail.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la investigación más reciente');
    }
  }

  Future<List<MarketingResearchDetail>> loadResearchHistory() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingResearchList,
        options: _backgroundOptions,
      );
      final rows = (res.data is List) ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) => MarketingResearchDetail.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar el historial de investigaciones');
    }
  }

  Future<void> forceResearchNow() async {
    try {
      await _dio.post(ApiRoutes.marketingResearchForce, data: const {});
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo generar la investigación manual');
    }
  }

  Future<MarketingLearningStats> loadLearningStats() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingResearchLearningStats,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingLearningStats.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar memorias/aprendizajes activos');
    }
  }

  Future<List<MarketingPublishedAsset>> loadPublishedAssets() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingPublishedAssets,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) => MarketingPublishedAsset.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar imágenes publicadas');
    }
  }
}
