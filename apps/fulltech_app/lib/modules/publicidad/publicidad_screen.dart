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

      state = state.copyWith(
        loading: false,
        dashboard: dashboard,
        config: config,
        dailyStories: stories,
        mediaAssets: mediaAssets,
        history: historyItems,
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
                                onActivate: controller.activateFlow,
                                onPause: controller.pauseFlow,
                                onGenerateNow: controller.generateNow,
                                onReset: controller.resetFlow,
                                busy: state.busy,
                              ),
                            if (_tab == _PublicidadTab.investigacion)
                              _ResearchSummaryTab(dashboard: state.dashboard),
                            if (_tab == _PublicidadTab.galeria)
                              _GalleryTab(
                                assets: state.mediaAssets,
                                busy: state.busy,
                                onCreate: controller.createMediaAsset,
                                onToggleActive: controller.toggleAssetActive,
                                onToggleFeatured: controller.toggleAssetFeatured,
                                onUpdateMeta: controller.updateAssetMeta,
                              ),
                            if (_tab == _PublicidadTab.estados)
                              _DailyStoriesTab(
                                stories: state.dailyStories,
                                mediaAssets: state.mediaAssets,
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
                label: Text('Configuraci├│n'),
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
    required this.onActivate,
    required this.onPause,
    required this.onGenerateNow,
    required this.onReset,
    required this.busy,
  });

  final PublicidadState state;
  final Future<void> Function() onActivate;
  final Future<void> Function() onPause;
  final Future<void> Function() onGenerateNow;
  final Future<void> Function() onReset;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final dashboard = state.dashboard;
    final cards = [
      ('Estado del flujo', dashboard?.flowStatus ?? 'INACTIVO'),
      ('Pendientes de aprobaci├│n', '${dashboard?.pendingApprovalCount ?? 0}'),
      ('Aprobados hoy', '${dashboard?.approvedTodayCount ?? 0}'),
      ('├Ültima generaci├│n', _formatDateTime(dashboard?.lastGenerationAt)),
      (
        'Pr├│xima generaci├│n sugerida',
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
      ],
    );
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
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onChangeBaseImage,
    required this.onEdit,
  });

  final List<MarketingStory> stories;
  final List<MarketingMediaAsset> mediaAssets;
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

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return const _EmptyState(
        text: 'No hay contenidos para la fecha seleccionada.',
      );
    }

    return Column(
      children: [
        for (final story in stories) ...[
          _StoryCard(
            story: story,
            busy: busy,
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
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.story,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onChangeBaseImage,
    required this.onEdit,
  });

  final MarketingStory story;
  final bool busy;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final Future<void> Function() onRegenerate;
  final Future<void> Function() onRegenerateImage;
  final Future<void> Function() onChangeBaseImage;
  final Future<void> Function() onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  story.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusPill(status: story.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(_storyTypeLabel(story.type)),
          const SizedBox(height: 6),
          Text(story.shortText),
          if (story.longText.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(story.longText, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Text(
            story.hashtags.join(' '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MetaChip(label: 'Fecha', value: _formatDate(story.date)),
              _MetaChip(label: 'Intentos', value: '${story.generationAttempt}'),
              _MetaChip(
                label: 'Categoría imagen',
                value: story.mediaAsset?.category ?? '-',
              ),
              _MetaChip(
                label: 'Estado imagen',
                value: story.imageStatus.name,
              ),
              _MetaChip(
                label: 'Imagen',
                value: story.imageUrl.trim().isEmpty
                    ? 'image_placeholder'
                    : story.imageUrl,
              ),
              _MetaChip(
                label: 'Prompt',
                value: story.imagePrompt.trim().isEmpty
                    ? '-'
                    : story.imagePrompt,
              ),
              _MetaChip(
                label: 'Concepto',
                value: story.visualConcept.trim().isEmpty
                    ? '-'
                    : story.visualConcept,
              ),
              _MetaChip(
                label: 'CTA',
                value: story.usedCTA.trim().isEmpty ? '-' : story.usedCTA,
              ),
              _MetaChip(
                label: 'Investigación usada',
                value: story.researchId ?? '-',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy ? null : onApprove,
                child: const Text('Aprobar'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onReject,
                child: const Text('Rechazar'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onRegenerate,
                child: const Text('Regenerar'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onRegenerateImage,
                child: const Text('Regenerar solo imagen'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onChangeBaseImage,
                child: const Text('Cambiar imagen base'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onEdit,
                child: const Text('Editar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResearchSummaryTab extends StatelessWidget {
  const _ResearchSummaryTab({required this.dashboard});

  final MarketingDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final research = dashboard?.latestResearch;
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
          Text(
            'Investigación automática',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: 'Estado', value: research.status),
              _MetaChip(
                label: 'Confianza',
                value: '${(research.confidenceScore * 100).toStringAsFixed(0)}%',
              ),
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
        ],
      ),
    );
  }
}

class _GalleryTab extends StatefulWidget {
  const _GalleryTab({
    required this.assets,
    required this.busy,
    required this.onCreate,
    required this.onToggleActive,
    required this.onToggleFeatured,
    required this.onUpdateMeta,
  });

  final List<MarketingMediaAsset> assets;
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
      ],
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
              _MetaChip(label: 'Uso', value: '${asset.useCount}'),
              _MetaChip(label: 'Último uso', value: _formatDateTime(asset.lastUsedAt)),
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
                '${_formatDate(item.date)}  ┬À  ${_storyTypeLabel(item.type)}  ┬À  Regenerado: ${item.regeneratedCount}x',
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
                        : 'Sin decisi├│n',
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
      return const _EmptyState(text: 'No se encontr├│ configuraci├│n del flujo.');
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
              label: const Text('Guardar configuraci├│n'),
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
                  decoration: const InputDecoration(labelText: 'T├¡tulo'),
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

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  return '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
