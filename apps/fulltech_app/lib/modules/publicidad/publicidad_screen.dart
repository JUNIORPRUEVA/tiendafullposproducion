import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'marketing_api.dart';
import 'marketing_models.dart';

enum _PublicidadTab {
  dashboard,
  investigacion,
  galeria,
  estados,
  historial,
  configuracion,
}

class PublicidadState {
  const PublicidadState({
    required this.loading,
    required this.busy,
    required this.date,
    required this.dashboard,
    required this.config,
    required this.dailyStories,
    required this.mediaAssets,
    required this.history,
    required this.latestResearch,
    required this.researchHistory,
    required this.learningStats,
    required this.publishedAssets,
    required this.error,
  });

  final bool loading;
  final bool busy;
  final DateTime date;
  final MarketingDashboard? dashboard;
  final MarketingFlowConfig? config;
  final List<MarketingStory> dailyStories;
  final List<MarketingMediaAsset> mediaAssets;
  final List<MarketingStory> history;
  final MarketingResearchDetail? latestResearch;
  final List<MarketingResearchDetail> researchHistory;
  final MarketingLearningStats? learningStats;
  final List<MarketingPublishedAsset> publishedAssets;
  final String? error;

  factory PublicidadState.initial() {
    final now = DateTime.now();
    return PublicidadState(
      loading: true,
      busy: false,
      date: DateTime(now.year, now.month, now.day),
      dashboard: null,
      config: null,
      dailyStories: const [],
      mediaAssets: const [],
      history: const [],
      latestResearch: null,
      researchHistory: const [],
      learningStats: null,
      publishedAssets: const [],
      error: null,
    );
  }

  PublicidadState copyWith({
    bool? loading,
    bool? busy,
    DateTime? date,
    MarketingDashboard? dashboard,
    MarketingFlowConfig? config,
    List<MarketingStory>? dailyStories,
    List<MarketingMediaAsset>? mediaAssets,
    List<MarketingStory>? history,
    MarketingResearchDetail? latestResearch,
    List<MarketingResearchDetail>? researchHistory,
    MarketingLearningStats? learningStats,
    List<MarketingPublishedAsset>? publishedAssets,
    String? error,
    bool clearError = false,
  }) {
    return PublicidadState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      date: date ?? this.date,
      dashboard: dashboard ?? this.dashboard,
      config: config ?? this.config,
      dailyStories: dailyStories ?? this.dailyStories,
      mediaAssets: mediaAssets ?? this.mediaAssets,
      history: history ?? this.history,
      latestResearch: latestResearch ?? this.latestResearch,
      researchHistory: researchHistory ?? this.researchHistory,
      learningStats: learningStats ?? this.learningStats,
      publishedAssets: publishedAssets ?? this.publishedAssets,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final publicidadControllerProvider =
    StateNotifierProvider<PublicidadController, PublicidadState>((ref) {
      return PublicidadController(ref.read(marketingApiProvider));
    });

class PublicidadController extends StateNotifier<PublicidadState> {
  PublicidadController(this._api) : super(PublicidadState.initial()) {
    loadInitial();
  }

  final MarketingApi _api;

  Future<void> loadInitial() async {
    await _refresh(keepLoading: true);
  }

  Future<void> refresh() async {
    await _refresh(keepLoading: false);
  }

  Future<void> changeDate(DateTime value) async {
    state = state.copyWith(date: DateTime(value.year, value.month, value.day));
    await _refresh(keepLoading: false);
  }

  Future<void> generateNow() async {
    await _runBusy(() async {
      await _api.generateMissing(state.date);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> approve(String storyId) async {
    await _runBusy(() async {
      await _api.approve(storyId);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> reject(String storyId, {String reason = ''}) async {
    await _runBusy(() async {
      await _api.reject(storyId, reason: reason);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> regenerate(String storyId) async {
    await _runBusy(() async {
      await _api.regenerate(storyId);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> regenerateImage(String storyId, {String? customPrompt}) async {
    await _runBusy(() async {
      await _api.regenerateImage(storyId, customPrompt: customPrompt);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> changeBaseImage(String storyId, String mediaAssetId) async {
    await _runBusy(() async {
      await _api.changeBaseImage(storyId, mediaAssetId);
      await _refresh(keepLoading: false);
    });
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
    await _runBusy(() async {
      await _api.editStory(
        storyId,
        title: title,
        shortText: shortText,
        longText: longText,
        hashtags: hashtags,
        imagePrompt: imagePrompt,
        imageUrl: imageUrl,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> activateFlow() async {
    await _runBusy(() async {
      await _api.activateFlow();
      await _refresh(keepLoading: false);
    });
  }

  Future<void> pauseFlow() async {
    await _runBusy(() async {
      await _api.pauseFlow();
      await _refresh(keepLoading: false);
    });
  }

  Future<void> resetFlow() async {
    await _runBusy(() async {
      await _api.resetFlow();
      await _refresh(keepLoading: false);
    });
  }

  Future<void> saveConfig(MarketingFlowConfig config) async {
    await _runBusy(() async {
      await _api.updateConfig(
        flujoActivo: config.active,
        pausado: config.paused,
        cantidadEstadosDiarios: config.dailyStoriesCount,
        horaGeneracion: config.generationTime,
        autoRegenerarSiNoAprueba: config.autoRegenerate,
        horasParaRegenerar: config.regenerateAfterHours,
        productosPrioritarios: config.priorityProducts,
        ciudadObjetivo: config.targetCity,
        tonoDeMarca: config.brandTone,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> createMediaAsset({
    required String fileUrl,
    required String fileName,
    required String category,
    String relatedService = '',
    String description = '',
    List<String> tags = const [],
  }) async {
    await _runBusy(() async {
      await _api.createMediaAsset(
        fileUrl: fileUrl,
        fileName: fileName,
        mimeType: _inferMimeType(fileName),
        category: category,
        relatedService: relatedService,
        description: description,
        tags: tags,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> toggleAssetActive(MarketingMediaAsset asset) async {
    await _runBusy(() async {
      await _api.updateMediaAsset(asset.id, isActive: !asset.isActive);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> toggleAssetFeatured(MarketingMediaAsset asset) async {
    await _runBusy(() async {
      await _api.updateMediaAsset(asset.id, isFeatured: !asset.isFeatured);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> updateAssetMeta(
    MarketingMediaAsset asset, {
    required String category,
    required String relatedService,
    required String tagsCsv,
    required String description,
  }) async {
    await _runBusy(() async {
      await _api.updateMediaAsset(
        asset.id,
        category: category,
        relatedService: relatedService,
        tags: tagsCsv
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        description: description,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> duplicatePublishedAsset(MarketingPublishedAsset item) async {
    await _runBusy(() async {
      final imageUrl = _resolvePublishedImageUrl(item);
      if (imageUrl.isEmpty) {
        throw StateError('No se pudo duplicar: el anuncio publicado no tiene imagen válida.');
      }

      final cleanType = _storyTypeLabelFromCode(item.storyType);
      final baseName = item.headline.trim().isEmpty
          ? 'anuncio-publicado'
          : item.headline.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      final safeName = '$baseName-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tags = <String>{
        ...item.hashtags.where((tag) => tag.trim().isNotEmpty).map((tag) => tag.trim()),
        'publicado',
        cleanType.toLowerCase(),
      };

      await _api.createMediaAsset(
        fileUrl: imageUrl,
        fileName: safeName,
        mimeType: _inferMimeType(safeName),
        category: 'Clientes / trabajos realizados',
        relatedService: cleanType,
        description: item.shortText,
        tags: tags.toList(growable: false),
      );

      await _refresh(keepLoading: false);
    });
  }

  Future<void> reusePublishedAssetInStory({
    required MarketingPublishedAsset asset,
    required String storyId,
  }) async {
    await _runBusy(() async {
      if (asset.mediaAssetId != null && asset.mediaAssetId!.trim().isNotEmpty) {
        await _api.changeBaseImage(storyId, asset.mediaAssetId!.trim());
        await _refresh(keepLoading: false);
        return;
      }

      final imageUrl = _resolvePublishedImageUrl(asset);
      if (imageUrl.isEmpty) {
        throw StateError('No se puede reutilizar este anuncio: no tiene imagen válida.');
      }

      final tempFileName = 'reuse-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final created = await _api.createMediaAsset(
        fileUrl: imageUrl,
        fileName: tempFileName,
        mimeType: _inferMimeType(tempFileName),
        category: 'Instalaciones reales',
        relatedService: _storyTypeLabelFromCode(asset.storyType),
        description: asset.shortText,
        tags: [
          ...asset.hashtags,
          'reutilizado',
          'publicado',
        ],
      );

      await _api.changeBaseImage(storyId, created.id);
      await _refresh(keepLoading: false);
    });
  }

  String _resolvePublishedImageUrl(MarketingPublishedAsset item) {
    final generated = item.generatedImageUrl.trim();
    if (generated.isNotEmpty) return generated;
    final fromAsset = item.mediaAsset?.fileUrl.trim() ?? '';
    if (fromAsset.isNotEmpty) return fromAsset;
    return '';
  }

  String _storyTypeLabelFromCode(String rawType) {
    switch (rawType.toUpperCase()) {
      case 'SALES':
        return 'Venta';
      case 'TRUST':
        return 'Confianza';
      case 'EDUCATIONAL':
        return 'Educativo';
      default:
        return rawType.trim().isEmpty ? 'General' : rawType.trim();
    }
  }

  Future<void> _refresh({required bool keepLoading}) async {
    try {
      state = state.copyWith(
        loading: keepLoading,
        busy: !keepLoading && state.busy,
        clearError: true,
      );

      final date = state.date;
      final from = date.subtract(const Duration(days: 14));
      final to = date;
      final dashboard = await _api.loadDashboard(date);
      final config = await _api.loadConfig();
      final mediaAssets = await _api.loadMediaAssets();
      var stories = const <MarketingStory>[];
      var historyItems = const <MarketingStory>[];
      MarketingResearchDetail? latestResearch;
      var researchHistory = const <MarketingResearchDetail>[];
      MarketingLearningStats? learningStats;
      var publishedAssets = const <MarketingPublishedAsset>[];
      String? softError;

      try {
        stories = await _api.loadStories(date);
      } catch (error) {
        softError = _friendlyError(
          error,
          fallback: 'No se pudieron cargar los estados diarios.',
        );
      }

      try {
        final history = await _api.loadHistory(from: from, to: to);
        historyItems = history.items;
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar el historial reciente.',
        );
      }

      try {
        latestResearch = await _api.loadLatestResearch();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar la investigación más reciente.',
        );
      }

      try {
        researchHistory = await _api.loadResearchHistory();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar el historial de investigaciones.',
        );
      }

      try {
        learningStats = await _api.loadLearningStats();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudieron cargar memorias de aprendizaje.',
        );
      }

      try {
        publishedAssets = await _api.loadPublishedAssets();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar la sección de imágenes publicadas.',
        );
      }

      state = state.copyWith(
        loading: false,
        dashboard: dashboard,
        config: config,
        dailyStories: stories,
        mediaAssets: mediaAssets,
        history: historyItems,
        latestResearch: latestResearch,
        researchHistory: researchHistory,
        learningStats: learningStats,
        publishedAssets: publishedAssets,
        error: softError,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        busy: false,
        error: _friendlyError(
          error,
          fallback: 'No se pudo actualizar el modulo Publicidad.',
        ),
      );
    }
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (state.busy) return;
    try {
      state = state.copyWith(busy: true, clearError: true);
      await task();
      state = state.copyWith(busy: false);
    } catch (error) {
      state = state.copyWith(
        busy: false,
        error: _friendlyError(
          error,
          fallback: 'No se pudo completar la accion solicitada.',
        ),
      );
    }
  }

  String _friendlyError(Object error, {required String fallback}) {
    if (error is ApiException) {
      final raw = error.message.trim();
      final normalized = raw.toLowerCase();
      final paginationError =
          error.code == 400 &&
          (normalized.contains('page must') ||
              normalized.contains('limit must'));
      if (paginationError) {
        return 'Se corrigio automaticamente la paginacion. Intenta actualizar de nuevo.';
      }

      if (raw.isEmpty || raw.startsWith('{') || raw.startsWith('[')) {
        return fallback;
      }
      return raw;
    }

    final raw = '$error'.trim();
    if (raw.isEmpty || raw.startsWith('{') || raw.startsWith('[')) {
      return fallback;
    }
    return raw;
  }

  String _inferMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

class PublicidadScreen extends ConsumerStatefulWidget {
  const PublicidadScreen({super.key});

  @override
  ConsumerState<PublicidadScreen> createState() => _PublicidadScreenState();
}

class _PublicidadScreenState extends ConsumerState<PublicidadScreen> {
  _PublicidadTab _tab = _PublicidadTab.dashboard;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final isAdmin =
        user != null &&
        hasPermission(user.appRole, AppPermission.viewPublicidad);

    if (!isAdmin) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad', showLogo: false),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final state = ref.watch(publicidadControllerProvider);
    final controller = ref.read(publicidadControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const CustomAppBar(title: 'Publicidad', fallbackRoute: '/home'),
      backgroundColor: scheme.surfaceContainerLowest,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.surface, scheme.surfaceContainerLowest],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _TopToolbar(
                  date: state.date,
                  tab: _tab,
                  busy: state.busy,
                  onPickDate: (value) => controller.changeDate(value),
                  onTabChanged: (value) => setState(() => _tab = value),
                  onRefresh: controller.refresh,
                ),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ErrorBanner(message: state.error!),
                ),
              Expanded(
                child: state.loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: controller.refresh,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          children: [
                            if (_tab == _PublicidadTab.dashboard)
                              _DashboardTab(
                                state: state,
                                stories: state.dailyStories,
                                mediaAssets: state.mediaAssets,
                                researches: state.researchHistory,
                                onActivate: controller.activateFlow,
                                onPause: controller.pauseFlow,
                                onGenerateNow: controller.generateNow,
                                onReset: controller.resetFlow,
                                onApprove: controller.approve,
                                onRegenerate: controller.regenerate,
                                onRegenerateImage: controller.regenerateImage,
                                onChangeBaseImage: controller.changeBaseImage,
                                busy: state.busy,
                              ),
                            if (_tab == _PublicidadTab.investigacion)
                              _ResearchSummaryTab(
                                dashboard: state.dashboard,
                                latestResearch: state.latestResearch,
                                researchHistory: state.researchHistory,
                                learningStats: state.learningStats,
                              ),
                            if (_tab == _PublicidadTab.galeria)
                              _GalleryTab(
                                assets: state.mediaAssets,
                                publishedAssets: state.publishedAssets,
                                stories: state.dailyStories,
                                busy: state.busy,
                                onCreate: controller.createMediaAsset,
                                onToggleActive: controller.toggleAssetActive,
                                onToggleFeatured: controller.toggleAssetFeatured,
                                onUpdateMeta: controller.updateAssetMeta,
                                onDuplicatePublished: controller.duplicatePublishedAsset,
                                onReusePublishedInStory: controller.reusePublishedAssetInStory,
                              ),
                            if (_tab == _PublicidadTab.estados)
                              _DailyStoriesTab(
                                stories: state.dailyStories,
                                mediaAssets: state.mediaAssets,
                                researches: state.researchHistory,
                                busy: state.busy,
                                onApprove: controller.approve,
                                onReject: controller.reject,
                                onRegenerate: controller.regenerate,
                                onRegenerateImage: controller.regenerateImage,
                                onChangeBaseImage: controller.changeBaseImage,
                                onEdit: (story, payload) {
                                  return controller.editStory(
                                    story.id,
                                    title: payload.title,
                                    shortText: payload.shortText,
                                    longText: payload.longText,
                                    hashtags: payload.hashtags,
                                    imagePrompt: payload.imagePrompt,
                                    imageUrl: payload.imageUrl,
                                  );
                                },
                              ),
                            if (_tab == _PublicidadTab.historial)
                              _HistoryTab(items: state.history),
                            if (_tab == _PublicidadTab.configuracion)
                              _ConfigTab(
                                config: state.config,
                                busy: state.busy,
                                onSave: controller.saveConfig,
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({
    required this.date,
    required this.tab,
    required this.busy,
    required this.onPickDate,
    required this.onTabChanged,
    required this.onRefresh,
  });

  final DateTime date;
  final _PublicidadTab tab;
  final bool busy;
  final ValueChanged<DateTime> onPickDate;
  final ValueChanged<_PublicidadTab> onTabChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Flujo de contenidos diarios',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) onPickDate(selected);
                      },
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<_PublicidadTab>(
            segments: const [
              ButtonSegment(
                value: _PublicidadTab.dashboard,
                label: Text('Dashboard'),
              ),
              ButtonSegment(
                value: _PublicidadTab.investigacion,
                label: Text('Investigación'),
              ),
              ButtonSegment(
                value: _PublicidadTab.galeria,
                label: Text('Galería Publicitaria'),
              ),
              ButtonSegment(
                value: _PublicidadTab.estados,
                label: Text('Estados diarios'),
              ),
              ButtonSegment(
                value: _PublicidadTab.historial,
                label: Text('Historial'),
              ),
              ButtonSegment(
                value: _PublicidadTab.configuracion,
                label: Text('Configuración'),
              ),
            ],
            selected: {tab},
            onSelectionChanged: (value) {
              if (value.isNotEmpty) onTabChanged(value.first);
            },
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.state,
    required this.stories,
    required this.mediaAssets,
    required this.researches,
    required this.onActivate,
    required this.onPause,
    required this.onGenerateNow,
    required this.onReset,
    required this.onApprove,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onChangeBaseImage,
    required this.busy,
  });

  final PublicidadState state;
  final List<MarketingStory> stories;
  final List<MarketingMediaAsset> mediaAssets;
  final List<MarketingResearchDetail> researches;
  final Future<void> Function() onActivate;
  final Future<void> Function() onPause;
  final Future<void> Function() onGenerateNow;
  final Future<void> Function() onReset;
  final Future<void> Function(String storyId) onApprove;
  final Future<void> Function(String storyId) onRegenerate;
  final Future<void> Function(String storyId, {String? customPrompt})
  onRegenerateImage;
  final Future<void> Function(String storyId, String mediaAssetId)
  onChangeBaseImage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dashboard = state.dashboard;
    final completeStories = stories.where(_isCompleteStory).length;
    final incompleteStories = stories.length - completeStories;
    final generatedImages = stories
      .where((s) => _safeImageUrl(s.generatedImageUrl).isNotEmpty)
      .length;
    final generatedCopies = stories
      .where(
        (s) =>
          s.title.trim().isNotEmpty &&
          s.shortText.trim().isNotEmpty &&
          s.usedCTA.trim().isNotEmpty,
      )
      .length;
    final cards = [
      ('Estado del flujo', dashboard?.flowStatus ?? 'INACTIVO'),
      ('Pendientes de aprobación', '${dashboard?.pendingApprovalCount ?? 0}'),
      ('Aprobados hoy', '${dashboard?.approvedTodayCount ?? 0}'),
      ('Última generación', _formatDateTime(dashboard?.lastGenerationAt)),
      (
        'Próxima generación sugerida',
        _formatDateTime(dashboard?.nextSuggestedGeneration),
      ),
      (
        'Investigación usable',
        dashboard?.researchUsable == true ? 'Sí' : 'No',
      ),
      (
        'Próxima investigación auto',
        _formatDateTime(dashboard?.nextAutoResearch),
      ),
      (
        'Frecuencia investigación',
        'Cada ${dashboard?.researchFrequencyDays ?? 2} días',
      ),
      ('Radio de servicio', '${dashboard?.serviceRadiusKm ?? 25} km'),
      ('Zona objetivo', dashboard?.serviceZone ?? 'Higüey, La Altagracia'),
      (
        'Estados con investigación actual',
        '${dashboard?.storiesFromCurrentResearch ?? 0}',
      ),
      ('Estados listos para revisión', '$completeStories'),
      ('Estados incompletos', '$incompleteStories'),
      ('Imágenes generadas', '$generatedImages'),
      ('Copys generados', '$generatedCopies'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards)
              SizedBox(
                width: 270,
                child: _MetricCard(label: card.$1, value: card.$2),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : onActivate,
              icon: const Icon(Icons.play_circle_fill_rounded),
              label: const Text('Activar flujo'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onPause,
              icon: const Icon(Icons.pause_circle_filled_rounded),
              label: const Text('Pausar flujo'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onGenerateNow,
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Generar estados ahora'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onReset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Eliminar/Reiniciar flujo'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Estados diarios',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _DailyStoriesTab(
          stories: stories,
          mediaAssets: mediaAssets,
          researches: researches,
          busy: busy,
          onApprove: onApprove,
          onReject: (_, {reason = ''}) async {},
          onRegenerate: onRegenerate,
          onRegenerateImage: onRegenerateImage,
          onChangeBaseImage: onChangeBaseImage,
          onEdit: (_, __) async {},
          compactActions: true,
        ),
      ],
    );
  }

  bool _isCompleteStory(MarketingStory story) {
    final hasImage =
        _safeImageUrl(story.generatedImageUrl).isNotEmpty ||
        _safeImageUrl(story.mediaAsset?.fileUrl).isNotEmpty ||
        _safeImageUrl(story.imageUrl).isNotEmpty;
    final hasCopy =
        story.title.trim().isNotEmpty &&
        story.shortText.trim().isNotEmpty &&
        story.usedCTA.trim().isNotEmpty;
    final hasPrompt = story.imagePrompt.trim().isNotEmpty;
    return hasImage && hasCopy && hasPrompt;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DailyStoriesTab extends StatelessWidget {
  const _DailyStoriesTab({
    required this.stories,
    required this.mediaAssets,
    required this.researches,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onChangeBaseImage,
    required this.onEdit,
    this.compactActions = false,
  });

  final List<MarketingStory> stories;
  final List<MarketingMediaAsset> mediaAssets;
  final List<MarketingResearchDetail> researches;
  final bool busy;
  final Future<void> Function(String storyId) onApprove;
  final Future<void> Function(String storyId, {String reason}) onReject;
  final Future<void> Function(String storyId) onRegenerate;
  final Future<void> Function(String storyId, {String? customPrompt})
  onRegenerateImage;
  final Future<void> Function(String storyId, String mediaAssetId)
  onChangeBaseImage;
  final Future<void> Function(MarketingStory story, _EditStoryPayload payload)
  onEdit;
  final bool compactActions;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return const _EmptyState(
        text:
            'No hay estados generados todavia. Presiona "Generar estados ahora".',
      );
    }

    final duplicateBaseIds = _findDuplicateBaseAssetIds(stories);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (duplicateBaseIds.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _ErrorBanner(
              message:
                  'Validacion: hay estados usando la misma imagen base. Regenera o cambia imagen para mantener variedad.',
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final width = constraints.maxWidth;
            final columns = width >= 1380 ? 3 : width >= 860 ? 2 : 1;
            final cardWidth = (width - (spacing * (columns - 1))) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final story in stories)
                  SizedBox(
                    width: cardWidth,
                    child: _StoryCard(
                      story: story,
                      usedResearch: _findResearch(story.researchId),
                      busy: busy,
                      compactActions: compactActions,
                      onApprove: () => onApprove(story.id),
                      onReject: () => onReject(story.id),
                      onRegenerate: () => onRegenerate(story.id),
                      onRegenerateImage: () => onRegenerateImage(story.id),
                      onChangeBaseImage: () async {
                        final chosen = await showDialog<String>(
                          context: context,
                          builder: (_) => _PickMediaAssetDialog(
                            assets: mediaAssets,
                            selectedId: story.mediaAssetId,
                          ),
                        );
                        if (chosen != null && chosen.isNotEmpty) {
                          await onChangeBaseImage(story.id, chosen);
                        }
                      },
                      onEdit: () async {
                        final payload = await showDialog<_EditStoryPayload>(
                          context: context,
                          builder: (_) => _EditStoryDialog(story: story),
                        );
                        if (payload != null) {
                          await onEdit(story, payload);
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  MarketingResearchDetail? _findResearch(String? id) {
    final target = (id ?? '').trim();
    if (target.isEmpty) return null;
    for (final item in researches) {
      if (item.id == target) return item;
    }
    return null;
  }

  Set<String> _findDuplicateBaseAssetIds(List<MarketingStory> rows) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final row in rows) {
      final id = row.mediaAssetId?.trim() ?? '';
      if (id.isEmpty) continue;
      if (!seen.add(id)) {
        duplicates.add(id);
      }
    }
    return duplicates;
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.story,
    required this.usedResearch,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onChangeBaseImage,
    required this.onEdit,
    this.compactActions = false,
  });

  final MarketingStory story;
  final MarketingResearchDetail? usedResearch;
  final bool busy;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final Future<void> Function() onRegenerate;
  final Future<void> Function() onRegenerateImage;
  final Future<void> Function() onChangeBaseImage;
  final Future<void> Function() onEdit;
  final bool compactActions;

  @override
  Widget build(BuildContext context) {
    final baseImage = _safeImageUrl(story.mediaAsset?.fileUrl ?? story.imageUrl);
    final generatedImage = _safeImageUrl(story.generatedImageUrl);
    final finalImage = _resolveFinalImage(story);
    final relatedService = (story.mediaAsset?.relatedService ?? story.usedOffer).trim();
    final cta = story.usedCTA.trim().isEmpty
        ? 'Escribenos por WhatsApp para cotizar'
        : story.usedCTA.trim();
    final approved = story.status == MarketingStoryStatus.approved;
    final missing = _missingFields(story);
    final isComplete = missing.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isComplete)
          _ErrorBanner(
            message:
                'Este anuncio está incompleto: falta ${missing.join(', ')}.',
          ),
        Row(
          children: [
            _MetaChip(label: 'Tipo', value: _storyTypeShort(story.type)),
            const SizedBox(width: 8),
            _StatusPill(status: story.status),
            if (approved) ...[
              const SizedBox(width: 8),
              const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 4),
              const Text(
                'Aprobado',
                style: TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 210,
            child: _StoryPreviewFrame(
              label: 'Preview final listo para publicar',
              imageUrl: finalImage,
              story: story,
              fallbackLabel: 'Genera imagen para este anuncio',
              showLabel: false,
              showApprovedBadge: approved,
            ),
          ),
        ),
        if (finalImage.isEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onRegenerateImage,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('Generar imagen'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StoryPreviewFrame(
                label: 'Imagen base seleccionada',
                imageUrl: baseImage,
                story: story,
                fallbackLabel: 'Sin imagen disponible',
                compact: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StoryPreviewFrame(
                label: 'Imagen final',
                imageUrl: finalImage,
                story: story,
                fallbackLabel: 'Generar imagen',
                compact: true,
                showApprovedBadge: approved,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _MetaChip(label: 'Investigación usada', value: story.researchId ?? '-'),
            _MetaChip(label: 'Servicio', value: relatedService.isEmpty ? '-' : relatedService),
            _MetaChip(label: 'CTA', value: cta),
            _MetaChip(label: 'Estado imagen', value: story.imageStatus.name),
            _MetaChip(label: 'Fecha generación', value: _formatDateTime(story.updatedAt ?? story.date)),
          ],
        ),
        const SizedBox(height: 8),
        _InfoLine(label: 'Headline', value: story.title),
        _InfoLine(label: 'Texto corto para historia', value: story.shortText),
        _InfoLine(label: 'Texto largo para post', value: story.longText),
        _InfoLine(label: 'Notas de diseño', value: story.designNotes),
        _InfoLine(label: 'Prompt de imagen', value: story.imagePrompt),
        _InfoLine(label: 'Concepto visual', value: story.visualConcept),
        _InfoLine(
          label: 'Hashtags',
          value: story.hashtags.isEmpty ? '-' : story.hashtags.join(' '),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy || !isComplete ? null : onApprove,
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('Aprobar estado'),
            ),
            OutlinedButton(
              onPressed: busy ? null : onRegenerate,
              child: const Text('Regenerar contenido'),
            ),
            OutlinedButton(
              onPressed: busy ? null : onRegenerateImage,
              child: const Text('Regenerar imagen'),
            ),
            OutlinedButton(
              onPressed: busy ? null : onChangeBaseImage,
              child: const Text('Cambiar imagen manual'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openFullscreenPreview(context, story, generatedImage, baseImage),
              icon: const Icon(Icons.open_in_full_rounded, size: 18),
              label: const Text('Ver anuncio completo'),
            ),
            OutlinedButton.icon(
              onPressed: usedResearch == null
                  ? null
                  : () => _openResearchUsed(context, usedResearch!),
              icon: const Icon(Icons.science_rounded, size: 18),
              label: const Text('Ver investigación usada'),
            ),
            if (!compactActions)
              OutlinedButton(
                onPressed: busy ? null : onReject,
                child: const Text('Rechazar'),
              ),
            if (!compactActions)
              OutlinedButton(
                onPressed: busy ? null : onEdit,
                child: const Text('Editar'),
              ),
          ],
        ),
      ],
    );
  }

  void _openFullscreenPreview(
    BuildContext context,
    MarketingStory story,
    String generatedImage,
    String baseImage,
  ) {
    final image = generatedImage.isNotEmpty
        ? generatedImage
        : baseImage;
    final missing = _missingFields(story);
    final canApprove = missing.isEmpty && !busy;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _StoryFullscreenPreview(
          story: story,
          imageUrl: image,
          canApprove: canApprove,
          onApprove: onApprove,
        ),
      ),
    );
  }

  void _openResearchUsed(BuildContext context, MarketingResearchDetail detail) {
    showDialog<void>(
      context: context,
      builder: (_) => _ResearchDetailDialog(research: detail),
    );
  }

  List<String> _missingFields(MarketingStory story) {
    final missing = <String>[];
    final hasImage =
        _safeImageUrl(story.generatedImageUrl).isNotEmpty ||
        _safeImageUrl(story.mediaAsset?.fileUrl).isNotEmpty ||
        _safeImageUrl(story.imageUrl).isNotEmpty;
    if (!hasImage) missing.add('imagen');
    if (story.imagePrompt.trim().isEmpty) missing.add('prompt');
    final hasCopy =
        story.title.trim().isNotEmpty &&
        story.shortText.trim().isNotEmpty &&
        story.usedCTA.trim().isNotEmpty;
    if (!hasCopy) missing.add('copy');
    return missing;
  }

  String _resolveFinalImage(MarketingStory story) {
    final generated = _safeImageUrl(story.generatedImageUrl);
    if (generated.isNotEmpty) return generated;
    final fromAsset = _safeImageUrl(story.mediaAsset?.fileUrl);
    if (fromAsset.isNotEmpty) return fromAsset;
    return '';
  }
}

class _StoryPreviewFrame extends StatelessWidget {
  const _StoryPreviewFrame({
    required this.label,
    required this.imageUrl,
    required this.story,
    required this.fallbackLabel,
    this.showLabel = true,
    this.compact = false,
    this.showApprovedBadge = false,
  });

  final String label;
  final String imageUrl;
  final MarketingStory story;
  final String fallbackLabel;
  final bool showLabel;
  final bool compact;
  final bool showApprovedBadge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel)
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (showLabel) const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 10 : 18),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  _StoryImageView(url: imageUrl)
                else
                  const _BrokenImagePlaceholder(),
                _StoryVisualOverlay(
                  type: story.type,
                  headline: story.title,
                  subtitle: story.shortText,
                  cta: story.usedCTA,
                  fallbackLabel: imageUrl.isEmpty ? fallbackLabel : null,
                  compact: compact,
                  approved: showApprovedBadge,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryImageView extends StatelessWidget {
  const _StoryImageView({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:image/') && url.contains(';base64,')) {
      try {
        final payload = url.split(';base64,').last;
        return Image.memory(
          base64Decode(payload),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
        );
      } catch (_) {
        return const _BrokenImagePlaceholder();
      }
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
      );
    }

    return const _BrokenImagePlaceholder();
  }
}

class _StoryVisualOverlay extends StatelessWidget {
  const _StoryVisualOverlay({
    required this.type,
    required this.headline,
    required this.subtitle,
    required this.cta,
    required this.fallbackLabel,
    required this.compact,
    required this.approved,
  });

  final MarketingStoryType type;
  final String headline;
  final String subtitle;
  final String cta;
  final String? fallbackLabel;
  final bool compact;
  final bool approved;

  @override
  Widget build(BuildContext context) {
    final accent = switch (type) {
      MarketingStoryType.sales => const Color(0xFFF97316),
      MarketingStoryType.trust => const Color(0xFF10B981),
      MarketingStoryType.educational => const Color(0xFF38BDF8),
    };

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0x12000000),
            Color.alphaBlend(accent.withValues(alpha: 0.2), const Color(0x99000000)),
          ],
        ),
      ),
      padding: EdgeInsets.all(compact ? 8 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xB3000000),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'FULLTECH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 9 : 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (fallbackLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xCC7C2D12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    fallbackLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const Spacer(),
              if (approved)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 24),
            ],
          ),
          const Spacer(),
          Text(
            headline,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 14 : 24,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          SizedBox(height: compact ? 4 : 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: const Color(0xFFF1F5F9),
              fontSize: compact ? 10 : 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 5 : 7),
            decoration: BoxDecoration(
              color: const Color(0xFFD7F9E9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              cta.trim().isEmpty ? 'Escribenos por WhatsApp' : cta.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF054A2A),
                fontWeight: FontWeight.w700,
                fontSize: compact ? 10 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryFullscreenPreview extends StatelessWidget {
  const _StoryFullscreenPreview({
    required this.story,
    required this.imageUrl,
    required this.canApprove,
    required this.onApprove,
  });

  final MarketingStory story;
  final String imageUrl;
  final bool canApprove;
  final Future<void> Function() onApprove;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl.isNotEmpty)
                        _StoryImageView(url: imageUrl)
                      else
                        const _BrokenImagePlaceholder(),
                      _StoryVisualOverlay(
                        type: story.type,
                        headline: story.title,
                        subtitle: story.shortText,
                        cta: story.usedCTA,
                        fallbackLabel: imageUrl.isEmpty ? 'Sin imagen disponible' : null,
                        compact: false,
                        approved: story.status == MarketingStoryStatus.approved,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FilledButton.icon(
                onPressed: canApprove
                    ? () async {
                        await onApprove();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                    : null,
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Aprobar estado'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
        ),
      ),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, color: Color(0xFF64748B), size: 30),
          SizedBox(height: 6),
          Text(
            'Sin imagen',
            style: TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

class _ResearchSummaryTab extends StatelessWidget {
  const _ResearchSummaryTab({
    required this.dashboard,
    required this.latestResearch,
    required this.researchHistory,
    required this.learningStats,
  });

  final MarketingDashboard? dashboard;
  final MarketingResearchDetail? latestResearch;
  final List<MarketingResearchDetail> researchHistory;
  final MarketingLearningStats? learningStats;

  @override
  Widget build(BuildContext context) {
    final research = latestResearch;
    if (research == null) {
      return const _EmptyState(
        text:
            'No hay investigación todavía. El sistema la generará automáticamente o puedes generar estados para forzarla.',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
            alpha: 0.35,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Investigación automática completa',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: researchHistory.isEmpty
                    ? null
                    : () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => _ResearchHistoryDialog(
                            items: researchHistory,
                          ),
                        );
                      },
                icon: const Icon(Icons.history_rounded),
                label: const Text('Ver historial de investigaciones'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: 'Estado', value: research.status),
              _MetaChip(label: 'Fecha investigación', value: _formatDate(research.date)),
              _MetaChip(label: 'Fuente usada', value: research.dataSources.isEmpty ? '-' : research.dataSources.join(', ')),
              _MetaChip(
                label: 'Confianza',
                value: '${(research.confidenceScore * 100).toStringAsFixed(0)}%',
              ),
              _MetaChip(label: 'Tema investigado', value: research.mainFocus.isEmpty ? '-' : research.mainFocus),
              _MetaChip(
                label: 'Frecuencia',
                value: 'Cada ${dashboard?.researchFrequencyDays ?? 2} días',
              ),
              _MetaChip(
                label: 'Próxima auto',
                value: _formatDateTime(dashboard?.nextAutoResearch),
              ),
              _MetaChip(
                label: 'Radio servicio',
                value: '${dashboard?.serviceRadiusKm ?? 25} km',
              ),
              _MetaChip(
                label: 'Zona',
                value: dashboard?.serviceZone ?? 'Higüey, La Altagracia',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ResearchField(label: 'Resumen del mercado', value: research.marketSummary),
          _ResearchField(
            label: 'Patrones de competidores',
            value: research.competitorPublishingPatterns,
          ),
          _ResearchField(label: 'Ofertas comunes', value: research.commonOffers),
          _ResearchField(
            label: 'Rangos de precios observados',
            value: research.observedPriceRanges,
          ),
          _ResearchField(
            label: 'Oportunidades para FULLTECH',
            value: research.contentOpportunities,
          ),
          _ResearchField(
            label: 'Recomendaciones para estados',
            value: research.recommendedHooks.join(' | '),
          ),
          _ResearchField(
            label: 'Recomendaciones de contenido',
            value: research.recommendedContentTypes.join(' | '),
          ),
          _ResearchField(label: 'Qué repetir', value: research.doMoreOfThis.join(' | ')),
          _ResearchField(label: 'Qué evitar', value: research.avoidThis.join(' | ')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                label: 'Ángulos fuertes',
                value: research.strongAngles.isEmpty
                    ? '-'
                    : research.strongAngles.join(' | '),
              ),
              _MetaChip(
                label: 'Ángulos débiles',
                value: research.weakAngles.isEmpty
                    ? '-'
                    : research.weakAngles.join(' | '),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Memorias/aprendizajes activos',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (learningStats == null || learningStats!.topInsights.isEmpty)
            const Text('No hay memorias activas todavía.')
          else
            Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      label: 'Activas',
                      value: '${learningStats!.activeCount}',
                    ),
                    _MetaChip(
                      label: 'Descartadas',
                      value: '${learningStats!.discardedCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final insight in learningStats!.topInsights)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '- [${insight.category}] ${insight.insight} (score ${insight.score.toStringAsFixed(2)})',
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResearchField extends StatelessWidget {
  const _ResearchField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(text),
        ],
      ),
    );
  }
}

class _ResearchHistoryDialog extends StatelessWidget {
  const _ResearchHistoryDialog({required this.items});

  final List<MarketingResearchDetail> items;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Historial de investigaciones'),
      content: SizedBox(
        width: 760,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final item = items[index];
            return ListTile(
              title: Text(item.mainFocus.isEmpty ? 'Investigación sin tema' : item.mainFocus),
              subtitle: Text(
                '${_formatDate(item.date)} · ${item.status} · ${(item.confidenceScore * 100).toStringAsFixed(0)}%',
              ),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => _ResearchDetailDialog(research: item),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ResearchDetailDialog extends StatelessWidget {
  const _ResearchDetailDialog({required this.research});

  final MarketingResearchDetail research;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Detalle de investigación'),
      content: SizedBox(
        width: 840,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResearchField(label: 'Fecha', value: _formatDateTime(research.createdAt ?? research.date)),
              _ResearchField(label: 'Estado', value: research.status),
              _ResearchField(label: 'Nivel de confianza', value: '${(research.confidenceScore * 100).toStringAsFixed(0)}%'),
              _ResearchField(label: 'Tema investigado', value: research.mainFocus),
              _ResearchField(label: 'Prompt usado', value: research.researchPrompt),
              _ResearchField(label: 'Resumen del mercado', value: research.marketSummary),
              _ResearchField(label: 'Patrones de competidores', value: research.competitorPublishingPatterns),
              _ResearchField(label: 'Ofertas comunes', value: research.commonOffers),
              _ResearchField(label: 'Rangos de precios observados', value: research.observedPriceRanges),
              _ResearchField(label: 'Ángulos fuertes', value: research.strongAngles.join(' | ')),
              _ResearchField(label: 'Ángulos débiles', value: research.weakAngles.join(' | ')),
              _ResearchField(label: 'Oportunidades para FULLTECH', value: research.contentOpportunities),
              _ResearchField(label: 'Recomendaciones de contenido', value: research.recommendedContentTypes.join(' | ')),
              _ResearchField(label: 'Recomendaciones para estados', value: research.recommendedHooks.join(' | ')),
              _ResearchField(label: 'Qué repetir', value: research.doMoreOfThis.join(' | ')),
              _ResearchField(label: 'Qué evitar', value: research.avoidThis.join(' | ')),
              _ResearchField(label: 'Fuentes usadas', value: research.dataSources.join(' | ')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _GalleryTab extends StatefulWidget {
  const _GalleryTab({
    required this.assets,
    required this.publishedAssets,
    required this.stories,
    required this.busy,
    required this.onCreate,
    required this.onToggleActive,
    required this.onToggleFeatured,
    required this.onUpdateMeta,
    required this.onDuplicatePublished,
    required this.onReusePublishedInStory,
  });

  final List<MarketingMediaAsset> assets;
  final List<MarketingPublishedAsset> publishedAssets;
  final List<MarketingStory> stories;
  final bool busy;
  final Future<void> Function({
    required String fileUrl,
    required String fileName,
    required String category,
    String relatedService,
    String description,
    List<String> tags,
  }) onCreate;
  final Future<void> Function(MarketingMediaAsset asset) onToggleActive;
  final Future<void> Function(MarketingMediaAsset asset) onToggleFeatured;
  final Future<void> Function(
    MarketingMediaAsset asset, {
    required String category,
    required String relatedService,
    required String tagsCsv,
    required String description,
  }) onUpdateMeta;
  final Future<void> Function(MarketingPublishedAsset item) onDuplicatePublished;
  final Future<void> Function({
    required MarketingPublishedAsset asset,
    required String storyId,
  }) onReusePublishedInStory;

  @override
  State<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<_GalleryTab> {
  String _category = 'Instalaciones reales';
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _serviceCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _filterCategory = 'Todos';

  static const _categories = [
    'Motores de portones',
    'Cámaras de seguridad',
    'Cercos eléctricos',
    'Intercoms',
    'Alarmas',
    'POS',
    'Instalaciones reales',
    'Equipo técnico',
    'Tienda física',
    'Clientes / trabajos realizados',
    'Tecnología general',
  ];

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    _serviceCtrl.dispose();
    _tagsCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filterCategory == 'Todos'
        ? widget.assets
        : widget.assets.where((item) => item.category == _filterCategory).toList(growable: false);
    final published = widget.publishedAssets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              TextFormField(
                controller: _urlCtrl,
                decoration: const InputDecoration(labelText: 'URL de imagen'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre archivo'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: _categories
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(growable: false),
                onChanged: (v) => setState(() => _category = v ?? _category),
                decoration: const InputDecoration(labelText: 'Categoría'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _serviceCtrl,
                decoration: const InputDecoration(labelText: 'Producto/servicio relacionado'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(labelText: 'Tags (coma separada)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () async {
                          await widget.onCreate(
                            fileUrl: _urlCtrl.text.trim(),
                            fileName: _nameCtrl.text.trim(),
                            category: _category,
                            relatedService: _serviceCtrl.text.trim(),
                            description: _descCtrl.text.trim(),
                            tags: _tagsCtrl.text
                                .split(',')
                                .map((item) => item.trim())
                                .where((item) => item.isNotEmpty)
                                .toList(growable: false),
                          );
                          _urlCtrl.clear();
                          _nameCtrl.clear();
                          _serviceCtrl.clear();
                          _tagsCtrl.clear();
                          _descCtrl.clear();
                        },
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('Subir imagen a galería'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _filterCategory,
          items: ['Todos', ..._categories]
              .map((e) => DropdownMenuItem(value: e, child: Text('Filtro: $e')))
              .toList(growable: false),
          onChanged: (v) => setState(() => _filterCategory = v ?? 'Todos'),
        ),
        const SizedBox(height: 10),
        Text(
          'Galería disponible',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const _EmptyState(text: 'No hay imágenes en la galería publicitaria.')
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in visible)
                SizedBox(
                  width: 300,
                  child: _GalleryAssetCard(
                    asset: item,
                    busy: widget.busy,
                    onToggleActive: () => widget.onToggleActive(item),
                    onToggleFeatured: () => widget.onToggleFeatured(item),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 14),
        Text(
          'Imágenes publicadas',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (published.isEmpty)
          const _EmptyState(text: 'Aún no hay anuncios aprobados para publicar en esta lista.')
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in published)
                SizedBox(
                  width: 320,
                  child: _PublishedAssetCard(
                    item: item,
                    busy: widget.busy,
                    onDuplicate: () => widget.onDuplicatePublished(item),
                    onReuse: () async {
                      final storyId = await _pickStoryForReuse(context);
                      if (storyId == null || storyId.isEmpty) return;
                      await widget.onReusePublishedInStory(asset: item, storyId: storyId);
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<String?> _pickStoryForReuse(BuildContext context) async {
    final stories = widget.stories.where((item) {
      final status = item.status.name.toUpperCase();
      return status == 'PENDING_APPROVAL' || status == 'REGENERATED';
    }).toList(growable: false);

    if (stories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay estados pendientes para reutilizar imagen.'),
        ),
      );
      return null;
    }

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reutilizar imagen en estado'),
        content: SizedBox(
          width: 560,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: stories.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final story = stories[index];
              return ListTile(
                title: Text(story.title),
                subtitle: Text('${_storyTypeLabel(story.type)} · ${story.status}'),
                onTap: () => Navigator.of(context).pop(story.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

class _PublishedAssetCard extends StatelessWidget {
  const _PublishedAssetCard({
    required this.item,
    required this.busy,
    required this.onDuplicate,
    required this.onReuse,
  });

  final MarketingPublishedAsset item;
  final bool busy;
  final Future<void> Function() onDuplicate;
  final Future<void> Function() onReuse;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _resolveImageUrl(item);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: imageUrl.isEmpty
                  ? const _BrokenImagePlaceholder()
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(item.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaChip(label: 'Tipo', value: _storyTypeLabelFromCode(item.storyType)),
              _MetaChip(label: 'Estado', value: item.status),
              _MetaChip(label: 'Aprobado', value: _formatDateTime(item.approvedAt)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showStoryPreview(context, item),
                icon: const Icon(Icons.open_in_full_rounded),
                label: const Text('Ver anuncio'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onReuse,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Reutilizar imagen'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onDuplicate,
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Duplicar para nuevo estado'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _resolveImageUrl(MarketingPublishedAsset item) {
    final generated = item.generatedImageUrl.trim();
    if (generated.isNotEmpty) return generated;
    final fromAsset = item.mediaAsset?.fileUrl.trim() ?? '';
    if (fromAsset.isNotEmpty) return fromAsset;
    return '';
  }

  String _storyTypeLabelFromCode(String rawType) {
    switch (rawType.toUpperCase()) {
      case 'SALES':
        return 'Venta';
      case 'TRUST':
        return 'Confianza';
      case 'EDUCATIONAL':
        return 'Educativo';
      default:
        return rawType.trim().isEmpty ? 'General' : rawType.trim();
    }
  }

  void _showStoryPreview(BuildContext context, MarketingPublishedAsset item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anuncio publicado'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 9 / 16,
                child: _resolveImageUrl(item).isEmpty
                    ? const _BrokenImagePlaceholder()
                    : Image.network(
                        _resolveImageUrl(item),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
                      ),
              ),
              const SizedBox(height: 10),
              Text(item.headline, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(item.shortText),
              const SizedBox(height: 6),
              Text(item.cta),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _GalleryAssetCard extends StatelessWidget {
  const _GalleryAssetCard({
    required this.asset,
    required this.busy,
    required this.onToggleActive,
    required this.onToggleFeatured,
  });

  final MarketingMediaAsset asset;
  final bool busy;
  final Future<void> Function() onToggleActive;
  final Future<void> Function() onToggleFeatured;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(asset.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(asset.fileUrl, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaChip(label: 'Categoría', value: asset.category),
              _MetaChip(label: 'Servicio', value: asset.relatedService ?? '-'),
              _MetaChip(
                label: 'Tags',
                value: asset.tags.isEmpty ? '-' : asset.tags.join(', '),
              ),
              _MetaChip(label: 'Uso', value: '${asset.useCount}'),
              _MetaChip(label: 'Último uso', value: _formatDateTime(asset.lastUsedAt)),
              _MetaChip(
                label: 'Usada en anuncio',
                value: asset.latestStoryTitle ?? '-',
              ),
              _MetaChip(
                label: 'Tipo anuncio',
                value: asset.latestStoryType ?? '-',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onToggleActive,
                child: Text(asset.isActive ? 'Desactivar' : 'Activar'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onToggleFeatured,
                child: Text(asset.isFeatured ? 'Quitar destacada' : 'Marcar destacada'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickMediaAssetDialog extends StatelessWidget {
  const _PickMediaAssetDialog({required this.assets, this.selectedId});

  final List<MarketingMediaAsset> assets;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar imagen base'),
      content: SizedBox(
        width: 520,
        child: assets.isEmpty
            ? const Text('No hay assets activos en la galería publicitaria.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: assets.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = assets[index];
                  return ListTile(
                    selected: item.id == selectedId,
                    title: Text(item.fileName),
                    subtitle: Text('${item.category} · uso ${item.useCount}'),
                    trailing: item.isFeatured ? const Icon(Icons.star_rounded) : null,
                    onTap: () => Navigator.of(context).pop(item.id),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.items});

  final List<MarketingStory> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(text: 'Sin actividad reciente en historial.');
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              leading: _StatusPill(status: item.status),
              title: Text(item.title),
              subtitle: Text(
                '${_formatDate(item.date)} · ${_storyTypeLabel(item.type)} · Regenerado: ${item.regeneratedCount}x',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.approvedByUserName.trim().isNotEmpty)
                    Text(
                      item.approvedByUserName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    item.approvedAt != null
                        ? 'Aprobado: ${_formatDateTime(item.approvedAt)}'
                        : item.rejectedAt != null
                        ? 'Rechazado: ${_formatDateTime(item.rejectedAt)}'
                        : 'Sin decisión',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfigTab extends StatefulWidget {
  const _ConfigTab({
    required this.config,
    required this.busy,
    required this.onSave,
  });

  final MarketingFlowConfig? config;
  final bool busy;
  final Future<void> Function(MarketingFlowConfig config) onSave;

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hour;
  late TextEditingController _count;
  late TextEditingController _regenerateHours;
  late TextEditingController _priorityProducts;
  late TextEditingController _targetCity;
  late TextEditingController _brandTone;
  late bool _active;
  late bool _paused;
  late bool _autoRegenerate;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _hour = TextEditingController(text: c?.generationTime ?? '08:00');
    _count = TextEditingController(text: '${c?.dailyStoriesCount ?? 3}');
    _regenerateHours = TextEditingController(
      text: '${c?.regenerateAfterHours ?? 6}',
    );
    _priorityProducts = TextEditingController(
      text: (c?.priorityProducts ?? const []).join(', '),
    );
    _targetCity = TextEditingController(text: c?.targetCity ?? '');
    _brandTone = TextEditingController(text: c?.brandTone ?? '');
    _active = c?.active ?? false;
    _paused = c?.paused ?? false;
    _autoRegenerate = c?.autoRegenerate ?? false;
  }

  @override
  void didUpdateWidget(covariant _ConfigTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config?.id == widget.config?.id) return;
    final c = widget.config;
    _hour.text = c?.generationTime ?? '08:00';
    _count.text = '${c?.dailyStoriesCount ?? 3}';
    _regenerateHours.text = '${c?.regenerateAfterHours ?? 6}';
    _priorityProducts.text = (c?.priorityProducts ?? const []).join(', ');
    _targetCity.text = c?.targetCity ?? '';
    _brandTone.text = c?.brandTone ?? '';
    _active = c?.active ?? false;
    _paused = c?.paused ?? false;
    _autoRegenerate = c?.autoRegenerate ?? false;
  }

  @override
  void dispose() {
    _hour.dispose();
    _count.dispose();
    _regenerateHours.dispose();
    _priorityProducts.dispose();
    _targetCity.dispose();
    _brandTone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final config = widget.config;
    if (config == null) {
      return const _EmptyState(text: 'No se encontró configuración del flujo.');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              value: _active,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _active = value),
              title: const Text('flujo_activo'),
            ),
            SwitchListTile.adaptive(
              value: _paused,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _paused = value),
              title: const Text('pausado'),
            ),
            SwitchListTile.adaptive(
              value: _autoRegenerate,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _autoRegenerate = value),
              title: const Text('auto_regenerar_si_no_aprueba'),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'cantidad_estados_diarios (default 3)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _hour,
              decoration: const InputDecoration(
                labelText: 'hora_generacion (HH:mm)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _regenerateHours,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'horas_para_regenerar (default 6)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priorityProducts,
              decoration: const InputDecoration(
                labelText: 'productos_prioritarios (coma separada)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _targetCity,
              decoration: const InputDecoration(labelText: 'ciudad_objetivo'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _brandTone,
              decoration: const InputDecoration(labelText: 'tono_de_marca'),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: widget.busy
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      final payload = MarketingFlowConfig(
                        id: config.id,
                        active: _active,
                        paused: _paused,
                        dailyStoriesCount:
                            int.tryParse(_count.text.trim()) ?? 3,
                        generationTime: _hour.text.trim().isEmpty
                            ? '08:00'
                            : _hour.text.trim(),
                        autoRegenerate: _autoRegenerate,
                        regenerateAfterHours:
                            int.tryParse(_regenerateHours.text.trim()) ?? 6,
                        priorityProducts: _priorityProducts.text
                            .split(',')
                            .map((item) => item.trim())
                            .where((item) => item.isNotEmpty)
                            .toList(growable: false),
                        targetCity: _targetCity.text.trim(),
                        brandTone: _brandTone.text.trim(),
                      );
                      await widget.onSave(payload);
                    },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar configuración'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final MarketingStoryStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, text) = switch (status) {
      MarketingStoryStatus.pending => (
        const Color(0xFFFFF3CD),
        const Color(0xFF7A5A00),
        'Pendiente',
      ),
      MarketingStoryStatus.approved => (
        const Color(0xFFD9FBE5),
        const Color(0xFF0E5F33),
        'Aprobado',
      ),
      MarketingStoryStatus.rejected => (
        const Color(0xFFFFE1E1),
        const Color(0xFF7B1A1A),
        'Rechazado',
      ),
      MarketingStoryStatus.regenerated => (
        const Color(0xFFE8EAF0),
        const Color(0xFF334155),
        'Regenerado',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      alignment: Alignment.center,
      child: Text(text),
    );
  }
}

class _EditStoryPayload {
  const _EditStoryPayload({
    required this.title,
    required this.shortText,
    required this.longText,
    required this.hashtags,
    required this.imagePrompt,
    required this.imageUrl,
  });

  final String title;
  final String shortText;
  final String longText;
  final List<String> hashtags;
  final String imagePrompt;
  final String imageUrl;
}

class _EditStoryDialog extends StatefulWidget {
  const _EditStoryDialog({required this.story});

  final MarketingStory story;

  @override
  State<_EditStoryDialog> createState() => _EditStoryDialogState();
}

class _EditStoryDialogState extends State<_EditStoryDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _shortText;
  late final TextEditingController _longText;
  late final TextEditingController _hashtags;
  late final TextEditingController _imagePrompt;
  late final TextEditingController _imageUrl;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.story.title);
    _shortText = TextEditingController(text: widget.story.shortText);
    _longText = TextEditingController(text: widget.story.longText);
    _hashtags = TextEditingController(text: widget.story.hashtags.join(' '));
    _imagePrompt = TextEditingController(text: widget.story.imagePrompt);
    _imageUrl = TextEditingController(text: widget.story.imageUrl);
  }

  @override
  void dispose() {
    _title.dispose();
    _shortText.dispose();
    _longText.dispose();
    _hashtags.dispose();
    _imagePrompt.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar contenido'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _shortText,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Texto corto'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _longText,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Texto largo'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _hashtags,
                  decoration: const InputDecoration(
                    labelText: 'Hashtags (separados por espacio)',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _imagePrompt,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Prompt de imagen',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'Imagen URL o image_placeholder',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop(
              _EditStoryPayload(
                title: _title.text,
                shortText: _shortText.text,
                longText: _longText.text,
                hashtags: _hashtags.text
                    .split(RegExp(r'\s+'))
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(growable: false),
                imagePrompt: _imagePrompt.text,
                imageUrl: _imageUrl.text.trim().isEmpty
                    ? 'image_placeholder'
                    : _imageUrl.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

String _storyTypeLabel(MarketingStoryType type) {
  switch (type) {
    case MarketingStoryType.sales:
      return 'Estado 1: Venta directa';
    case MarketingStoryType.trust:
      return 'Estado 2: Confianza / autoridad';
    case MarketingStoryType.educational:
      return 'Estado 3: Educativo / necesidad';
  }
}

String _storyTypeShort(MarketingStoryType type) {
  switch (type) {
    case MarketingStoryType.sales:
      return 'Venta';
    case MarketingStoryType.trust:
      return 'Confianza';
    case MarketingStoryType.educational:
      return 'Educativo';
  }
}

String _safeImageUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('data:image/')) return value;
  if (value.startsWith('image_placeholder')) return '';
  return value;
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  return '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
