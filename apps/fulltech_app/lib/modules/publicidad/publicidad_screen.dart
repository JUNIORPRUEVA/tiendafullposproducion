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
    required this.history,
    required this.error,
    required this.latestResearch,
    required this.researchConfig,
    required this.learningStats,
  });

  final bool loading;
  final bool busy;
  final DateTime date;
  final MarketingDashboard? dashboard;
  final MarketingFlowConfig? config;
  final List<MarketingStory> dailyStories;
  final List<MarketingStory> history;
  final String? error;
  final MarketingResearch? latestResearch;
  final MarketingResearchConfig? researchConfig;
  final MarketingLearningStats? learningStats;

  factory PublicidadState.initial() {
    final now = DateTime.now();
    return PublicidadState(
      loading: true,
      busy: false,
      date: DateTime(now.year, now.month, now.day),
      dashboard: null,
      config: null,
      dailyStories: const [],
      history: const [],
      error: null,
      latestResearch: null,
      researchConfig: null,
      learningStats: null,
    );
  }

  PublicidadState copyWith({
    bool? loading,
    bool? busy,
    DateTime? date,
    MarketingDashboard? dashboard,
    MarketingFlowConfig? config,
    List<MarketingStory>? dailyStories,
    List<MarketingStory>? history,
    String? error,
    bool clearError = false,
    MarketingResearch? latestResearch,
    bool clearLatestResearch = false,
    MarketingResearchConfig? researchConfig,
    MarketingLearningStats? learningStats,
  }) {
    return PublicidadState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      date: date ?? this.date,
      dashboard: dashboard ?? this.dashboard,
      config: config ?? this.config,
      dailyStories: dailyStories ?? this.dailyStories,
      history: history ?? this.history,
      error: clearError ? null : (error ?? this.error),
      latestResearch: clearLatestResearch
          ? null
          : (latestResearch ?? this.latestResearch),
      researchConfig: researchConfig ?? this.researchConfig,
      learningStats: learningStats ?? this.learningStats,
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

  Future<void> generateResearch({String? customPrompt}) async {
    await _runBusy(() async {
      final result = await _api.generateResearch(customPrompt: customPrompt);
      state = state.copyWith(latestResearch: result);
      final stats = await _api.loadLearningStats();
      state = state.copyWith(learningStats: stats);
    });
  }

  Future<void> forceResearch({String? customPrompt}) async {
    await _runBusy(() async {
      final result = await _api.forceResearch(customPrompt: customPrompt);
      state = state.copyWith(latestResearch: result);
      final stats = await _api.loadLearningStats();
      state = state.copyWith(learningStats: stats);
    });
  }

  Future<void> approveResearch(String researchId) async {
    await _runBusy(() async {
      await _api.approveResearch(researchId);
      final latest = await _api.loadLatestResearch();
      state = state.copyWith(
        latestResearch: latest,
        clearLatestResearch: latest == null,
      );
    });
  }

  Future<void> rejectResearch(String researchId, {String reason = ''}) async {
    await _runBusy(() async {
      await _api.rejectResearch(researchId, reason: reason);
      final latest = await _api.loadLatestResearch();
      state = state.copyWith(
        latestResearch: latest,
        clearLatestResearch: latest == null,
      );
    });
  }

  Future<void> saveResearchConfig(MarketingResearchConfig cfg) async {
    await _runBusy(() async {
      await _api.saveResearchConfig(
        defaultPrompt: cfg.defaultResearchPrompt,
        businessName: cfg.businessName,
        businessLocation: cfg.businessLocation,
        businessDescription: cfg.businessDescription,
        mainServices: cfg.mainServices,
        priorityServices: cfg.priorityServices,
        targetMarket: cfg.targetMarket,
        brandTone: cfg.brandTone,
        learningEnabled: cfg.learningEnabled,
        researchFrequencyDays: cfg.researchFrequencyDays,
        phone: cfg.phone,
        address: cfg.address,
        city: cfg.city,
        province: cfg.province,
        country: cfg.country,
        latitude: cfg.latitude,
        longitude: cfg.longitude,
        serviceRadiusKm: cfg.serviceRadiusKm,
        serviceZones: cfg.serviceZones,
        defaultCTA: cfg.defaultCTA,
        brandColors: cfg.brandColors,
        businessHours: cfg.businessHours,
        internalNotes: cfg.internalNotes,
      );
      final updatedConfig = await _api.loadResearchConfig();
      state = state.copyWith(researchConfig: updatedConfig);
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

      MarketingResearch? latestResearch;
      MarketingResearchConfig? researchConfig;
      MarketingLearningStats? learningStats;

      try {
        latestResearch = await _api.loadLatestResearch();
      } catch (_) {}

      try {
        researchConfig = await _api.loadResearchConfig();
      } catch (_) {}

      try {
        learningStats = await _api.loadLearningStats();
      } catch (_) {}

      state = state.copyWith(
        loading: false,
        dashboard: dashboard,
        config: config,
        dailyStories: stories,
        history: historyItems,
        error: softError,
        latestResearch: latestResearch,
        clearLatestResearch: latestResearch == null,
        researchConfig: researchConfig,
        learningStats: learningStats,
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
                  final researchCards = [
                    ('Última investigación', dashboard?.latestResearch?.status == 'APPROVED' ? 'Aprobada ✓' : 'Sin investigación'),
                    ('Investigación usable', dashboard?.researchUsable == true ? 'Sí ✓' : 'No'),
                    ('Próxima investigación auto', _formatDateTime(dashboard?.nextAutoResearch)),
                    ('Frecuencia investigación', 'Cada ${dashboard?.researchFrequencyDays ?? 2} días'),
                    ('Estados desde investigación actual', '${dashboard?.storiesFromCurrentResearch ?? 0}'),
                    ('Radio de servicio', '${dashboard?.serviceRadiusKm ?? 25} km'),
                    ('Zona objetivo', dashboard?.serviceZone ?? 'Higüey, La Altagracia'),
                            if (_tab == _PublicidadTab.investigacion)
                              _ResearchTab(
                                research: state.latestResearch,
                                researchConfig: state.researchConfig,
                                learningStats: state.learningStats,
                                busy: state.busy,
                                onGenerate: controller.generateResearch,
                                onForce: controller.forceResearch,
                                onApprove: controller.approveResearch,
                                onReject: controller.rejectResearch,
                                onSaveConfig: controller.saveResearchConfig,
                              ),
                            if (_tab == _PublicidadTab.estados)
                              _DailyStoriesTab(
                                stories: state.dailyStories,
                                busy: state.busy,
                                onApprove: controller.approve,
                                onReject: controller.reject,
                                onRegenerate: controller.regenerate,
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
  @override
  Widget build(BuildContext context) {
    final dashboard = state.dashboard;
    final flowCards = [
      ('Estado del flujo', dashboard?.flowStatus ?? 'INACTIVO'),
      ('Pendientes de aprobación', '${dashboard?.pendingApprovalCount ?? 0}'),
      ('Aprobados hoy', '${dashboard?.approvedTodayCount ?? 0}'),
      ('Última generación', _formatDateTime(dashboard?.lastGenerationAt)),
      ('Próxima generación sugerida', _formatDateTime(dashboard?.nextSuggestedGeneration)),
    ];
    final researchCards = [
      ('Última investigación', dashboard?.latestResearch?.status == 'APPROVED' ? 'Aprobada ✓' : dashboard?.latestResearch?.status == 'DRAFT' ? 'Borrador' : 'Sin investigación'),
      ('Investigación usable', dashboard?.researchUsable == true ? 'Sí ✓' : 'No'),
      ('Próxima investigación auto', _formatDateTime(dashboard?.nextAutoResearch)),
      ('Frecuencia investigación', 'Cada ${dashboard?.researchFrequencyDays ?? 2} días'),
      ('Estados desde investigación', '${dashboard?.storiesFromCurrentResearch ?? 0}'),
      ('Radio de servicio', '${dashboard?.serviceRadiusKm ?? 25} km'),
      ('Zona objetivo', dashboard?.serviceZone ?? 'Higüey, La Altagracia'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DashSectionHeader(label: 'Flujo de contenido'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in flowCards)
              SizedBox(width: 260, child: _MetricCard(label: card.$1, value: card.$2)),
          ],
        ),
        const SizedBox(height: 16),
        const _DashSectionHeader(label: 'Investigación de mercado'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in researchCards)
              SizedBox(width: 260, child: _MetricCard(label: card.$1, value: card.$2)),
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

class _DashSectionHeader extends StatelessWidget {
  const _DashSectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
            ('Última generación', _formatDateTime(dashboard?.lastGenerationAt)),
            ('Próxima generación sugerida', _formatDateTime(dashboard?.nextSuggestedGeneration)),
          ];
          final researchCards = [
            ('Última investigación', dashboard?.latestResearch?.status == 'APPROVED' ? 'Aprobada ✓' : 'Sin investigación'),
            ('Investigación usable', dashboard?.researchUsable == true ? 'Sí ✓' : 'No'),
            ('Próxima investigación auto', _formatDateTime(dashboard?.nextAutoResearch)),
            ('Frecuencia investigación', 'Cada ${dashboard?.researchFrequencyDays ?? 2} días'),
            ('Estados desde investigación actual', '${dashboard?.storiesFromCurrentResearch ?? 0}'),
            ('Radio de servicio', '${dashboard?.serviceRadiusKm ?? 25} km'),
            ('Zona objetivo', dashboard?.serviceZone ?? 'Higüey, La Altagracia'),
          ];

        final researchCards = [
          ('Última investigación', researchStatusLabel),
          ('Investigación usable', dashboard?.researchUsable == true ? 'Sí ✓' : 'No'),
          ('Próxima investigación auto', _formatDateTime(dashboard?.nextAutoResearch)),
          ('Frecuencia investigación', 'Cada ${dashboard?.researchFrequencyDays ?? 2} días'),
          ('Estados desde investigación actual', '${dashboard?.storiesFromCurrentResearch ?? 0}'),
          ('Radio de servicio', '${dashboard?.serviceRadiusKm ?? 25} km'),
          ('Zona objetivo', dashboard?.serviceZone ?? 'Higüey, La Altagracia'),
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
                for (final card in flowCards)
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
            OutlinedButton.icon(
              onPressed: busy ? null : onReset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Eliminar/Reiniciar flujo'),
            ),
          ],
        ),
        const SizedBox(height: 16),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _DashSectionHeader(label: 'Investigación de mercado'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in researchCards)
              SizedBox(width: 260, child: _MetricCard(label: card.$1, value: card.$2)),
          ],
        ),
      ],
    );
  }
}

class _DashSectionHeader extends StatelessWidget {
  const _DashSectionHeader({required this.label});
  final String label;
    ),
  );
}

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
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onEdit,
  });

  final List<MarketingStory> stories;
  final bool busy;
  final Future<void> Function(String storyId) onApprove;
  final Future<void> Function(String storyId, {String reason}) onReject;
  final Future<void> Function(String storyId) onRegenerate;
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
    required this.onEdit,
  });

  final MarketingStory story;
  final bool busy;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final Future<void> Function() onRegenerate;
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
                '${_formatDate(item.date)}  ·  ${_storyTypeLabel(item.type)}  ·  Regenerado: ${item.regeneratedCount}x',
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
  late TextEditingController _priorityProducts;
  late TextEditingController _targetCity;
  late TextEditingController _brandTone;
  late int _regenerateHoursValue;
  late bool _active;
  late bool _paused;
  late bool _autoRegenerate;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _hour = TextEditingController(text: c?.generationTime ?? '08:00');
    _count = TextEditingController(text: '${c?.dailyStoriesCount ?? 3}');
    _regenerateHoursValue = _normalizeRegenerateHours(c?.regenerateAfterHours);
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
    _regenerateHoursValue = _normalizeRegenerateHours(c?.regenerateAfterHours);
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
    _priorityProducts.dispose();
    _targetCity.dispose();
    _brandTone.dispose();
    super.dispose();
  }

  static const List<int> _regenerateOptions = [0, 1, 2, 3, 6, 12, 24, 48, 72];

  int _normalizeRegenerateHours(int? value) {
    final safe = value ?? 6;
    if (_regenerateOptions.contains(safe)) {
      return safe;
    }
    if (safe < 0) return 0;
    if (safe > 72) return 72;
    return safe;
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
            DropdownButtonFormField<int>(
              initialValue: _regenerateHoursValue,
              decoration: const InputDecoration(
                labelText: 'horas_para_regenerar',
                helperText: '0 = prueba inmediata',
              ),
              items: _regenerateOptions
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text(
                        value == 0 ? '0 (inmediato)' : '$value hora(s)',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: widget.busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _regenerateHoursValue = value);
                    },
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
                        regenerateAfterHours: _regenerateHoursValue,
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

class _ResearchTab extends StatefulWidget {
  const _ResearchTab({
    required this.research,
    required this.researchConfig,
    required this.learningStats,
    required this.busy,
    required this.onGenerate,
    required this.onForce,
    required this.onApprove,
    required this.onReject,
    required this.onSaveConfig,
  });

  final MarketingResearch? research;
  final MarketingResearchConfig? researchConfig;
  final MarketingLearningStats? learningStats;
  final bool busy;
  final Future<void> Function({String? customPrompt}) onGenerate;
  final Future<void> Function({String? customPrompt}) onForce;
  final Future<void> Function(String researchId) onApprove;
  final Future<void> Function(String researchId, {String reason}) onReject;
  final Future<void> Function(MarketingResearchConfig config) onSaveConfig;

  @override
  State<_ResearchTab> createState() => _ResearchTabState();
}

class _ResearchTabState extends State<_ResearchTab> {
  late TextEditingController _promptController;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(
      text: widget.researchConfig?.defaultResearchPrompt ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _ResearchTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.researchConfig?.id != widget.researchConfig?.id &&
        widget.researchConfig != null) {
      _promptController.text = widget.researchConfig!.defaultResearchPrompt;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final research = widget.research;
    final config = widget.researchConfig;
    final stats = widget.learningStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Prompt section ──────────────────────────────────────────────────
        _ResearchSection(
          title: 'Instrucción de investigación',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _promptController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Prompt de investigación',
                  helperText: 'Define qué analizar en el mercado.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              if (config != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: widget.busy
                          ? null
                          : () async {
                              final updatedConfig = MarketingResearchConfig(
                                id: config.id,
                                defaultResearchPrompt: _promptController.text
                                    .trim(),
                                businessName: config.businessName,
                                businessLocation: config.businessLocation,
                                businessDescription: config.businessDescription,
                                mainServices: config.mainServices,
                                priorityServices: config.priorityServices,
                                targetMarket: config.targetMarket,
                                brandTone: config.brandTone,
                                learningEnabled: config.learningEnabled,
                                researchFrequencyDays:
                                    config.researchFrequencyDays,
                                requireApproval: config.requireApproval,
                              );
                              await widget.onSaveConfig(updatedConfig);
                            },
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Guardar instrucción'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.busy
                          ? null
                          : () async {
                              await widget.onGenerate(
                                customPrompt:
                                    _promptController.text.trim().isEmpty
                                    ? null
                                    : _promptController.text.trim(),
                              );
                            },
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Generar investigación'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text(
                                    'Forzar nueva investigación',
                                  ),
                                  content: const Text(
                                    'Esto generará una nueva investigación aunque ya exista una reciente. ¿Continuar?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Forzar'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await widget.onForce(
                                  customPrompt:
                                      _promptController.text.trim().isEmpty
                                      ? null
                                      : _promptController.text.trim(),
                                );
                              }
                            },
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text('Forzar nueva investigación'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Latest research results ─────────────────────────────────────────
        if (research == null)
          const _EmptyState(
            text:
                'No hay investigación de mercado disponible. Genera una nueva.',
          )
        else ...[
          // Status + meta
          _ResearchSection(
            title: 'Última investigación',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ResearchStatusPill(status: research.status),
                    const SizedBox(width: 10),
                    Text(
                      'Confianza: ${(research.confidenceScore * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (research.createdAt != null)
                      Text(
                        _formatDateTime(research.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                if (research.dataSources.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: research.dataSources
                        .map((src) => _MetaChip(label: 'Fuente', value: src))
                        .toList(),
                  ),
                ],
                if (research.status == MarketingResearchStatus.draft) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: widget.busy
                            ? null
                            : () => widget.onApprove(research.id),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text('Aprobar investigación'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.busy
                            ? null
                            : () async {
                                final reason = await showDialog<String>(
                                  context: context,
                                  builder: (_) => const _TextInputDialog(
                                    title: 'Rechazar investigación',
                                    hint: 'Motivo (opcional)',
                                  ),
                                );
                                if (reason != null) {
                                  await widget.onReject(
                                    research.id,
                                    reason: reason,
                                  );
                                }
                              },
                        icon: const Icon(Icons.cancel_rounded, size: 18),
                        label: const Text('Rechazar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          if (research.marketSummary.trim().isNotEmpty)
            _ResearchSection(
              title: 'Resumen del mercado',
              child: Text(research.marketSummary),
            ),
          const SizedBox(height: 10),

          if (research.competitorPublishingPatterns.trim().isNotEmpty)
            _ResearchSection(
              title: 'Patrones de competidores',
              child: Text(research.competitorPublishingPatterns),
            ),
          const SizedBox(height: 10),

          if (research.commonOffers.trim().isNotEmpty)
            _ResearchSection(
              title: 'Ofertas comunes en el mercado',
              child: Text(research.commonOffers),
            ),
          const SizedBox(height: 10),

          if (research.observedPriceRanges.trim().isNotEmpty)
            _ResearchSection(
              title: 'Rangos de precios observados',
              child: Text(research.observedPriceRanges),
            ),
          const SizedBox(height: 10),

          if (research.strongAngles.isNotEmpty)
            _ResearchSection(
              title: 'Ángulos fuertes',
              child: _BulletList(
                items: research.strongAngles,
                color: const Color(0xFF0E5F33),
              ),
            ),
          const SizedBox(height: 10),

          if (research.weakAngles.isNotEmpty)
            _ResearchSection(
              title: 'Ángulos débiles',
              child: _BulletList(
                items: research.weakAngles,
                color: const Color(0xFF7B1A1A),
              ),
            ),
          const SizedBox(height: 10),

          if (research.contentOpportunities.trim().isNotEmpty)
            _ResearchSection(
              title: 'Oportunidades de contenido',
              child: Text(research.contentOpportunities),
            ),
          const SizedBox(height: 10),

          if (research.recommendedProducts.isNotEmpty)
            _ResearchSection(
              title: 'Productos recomendados',
              child: _BulletList(items: research.recommendedProducts),
            ),
          const SizedBox(height: 10),

          if (research.recommendedContentTypes.isNotEmpty)
            _ResearchSection(
              title: 'Tipos de contenido recomendados',
              child: _BulletList(items: research.recommendedContentTypes),
            ),
          const SizedBox(height: 10),

          if (research.recommendedOffers.isNotEmpty)
            _ResearchSection(
              title: 'Ofertas recomendadas',
              child: _BulletList(items: research.recommendedOffers),
            ),
          const SizedBox(height: 10),

          if (research.recommendedHooks.isNotEmpty)
            _ResearchSection(
              title: 'Hooks recomendados',
              child: _BulletList(items: research.recommendedHooks),
            ),
          const SizedBox(height: 10),

          if (research.recommendedCTAs.isNotEmpty)
            _ResearchSection(
              title: 'CTAs recomendados',
              child: _BulletList(items: research.recommendedCTAs),
            ),
          const SizedBox(height: 10),

          if (research.doMoreOfThis.isNotEmpty)
            _ResearchSection(
              title: 'Hacer más de esto ✓',
              child: _BulletList(
                items: research.doMoreOfThis,
                color: const Color(0xFF0E5F33),
              ),
            ),
          const SizedBox(height: 10),

          if (research.avoidThis.isNotEmpty)
            _ResearchSection(
              title: 'Evitar esto ✗',
              child: _BulletList(
                items: research.avoidThis,
                color: const Color(0xFF7B1A1A),
              ),
            ),
          const SizedBox(height: 14),
        ],

        // ── Learning stats ──────────────────────────────────────────────────
        if (stats != null)
          _ResearchSection(
            title: 'Aprendizaje acumulado',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _MetaChip(label: 'Activos', value: '${stats.activeCount}'),
                    _MetaChip(
                      label: 'Descartados',
                      value: '${stats.discardedCount}',
                    ),
                  ],
                ),
                if (stats.topInsights.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Top insights:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _BulletList(items: stats.topInsights),
                ],
              ],
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ResearchSection extends StatelessWidget {
  const _ResearchSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
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
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, this.color});

  final List<String> items;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: textStyle?.copyWith(fontWeight: FontWeight.w700),
                ),
                Expanded(child: Text(item, style: textStyle)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ResearchStatusPill extends StatelessWidget {
  const _ResearchStatusPill({required this.status});

  final MarketingResearchStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      MarketingResearchStatus.draft => (
        const Color(0xFFFFF3CD),
        const Color(0xFF7A5A00),
      ),
      MarketingResearchStatus.approved => (
        const Color(0xFFD9FBE5),
        const Color(0xFF0E5F33),
      ),
      MarketingResearchStatus.rejected => (
        const Color(0xFFFFE1E1),
        const Color(0xFF7B1A1A),
      ),
      MarketingResearchStatus.used => (
        const Color(0xFFE8EAF0),
        const Color(0xFF334155),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        researchStatusLabel(status),
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        decoration: InputDecoration(hintText: widget.hint),
        minLines: 2,
        maxLines: 4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('Confirmar'),
        ),
      ],
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

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  return '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
