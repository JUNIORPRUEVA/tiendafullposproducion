import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../application/media_gallery_controller.dart';
import '../media_gallery_models.dart';
import '../widgets/media_gallery_card.dart';

class MediaGalleryScreen extends ConsumerStatefulWidget {
  const MediaGalleryScreen({super.key});

  @override
  ConsumerState<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends ConsumerState<MediaGalleryScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 720) return;
    ref.read(mediaGalleryControllerProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final canView = auth.isAuthenticated &&
        auth.user != null &&
        hasPermission(auth.user!.appRole, AppPermission.viewMediaGallery);
    final state = ref.watch(mediaGalleryControllerProvider);
    final controller = ref.read(mediaGalleryControllerProvider.notifier);

    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Galería media')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta pantalla está disponible solo para administración y marketing.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final visibleItems = state.visibleItems;
    final totalItems = state.items.length;
    final completedCount = state.items
        .where((item) => item.isInstallationCompleted)
        .length;
    final pendingCount = totalItems - completedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Galería media'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: state.refreshing ? null : () => controller.refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                child: _GalleryHero(
                  totalItems: totalItems,
                  visibleItems: visibleItems.length,
                  completedCount: completedCount,
                  pendingCount: pendingCount,
                  state: state,
                  onTypeChanged: controller.setTypeFilter,
                  onInstallationChanged: controller.setInstallationFilter,
                ),
              ),
            ),
            if (state.loading && state.items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if ((state.error ?? '').trim().isNotEmpty &&
                state.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GalleryMessageState(
                  icon: Icons.perm_media_outlined,
                  title: 'No se pudo cargar la galería',
                  message: state.error!,
                  actionLabel: 'Reintentar',
                  onAction: () => controller.retry(),
                ),
              )
            else if (visibleItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GalleryMessageState(
                  icon: Icons.photo_library_outlined,
                  title: 'No hay medios para este filtro',
                  message:
                      'Prueba otra combinación entre tipo de archivo y estado de instalación.',
                  actionLabel: 'Mostrar todo',
                  onAction: () {
                    controller.setTypeFilter(MediaGalleryTypeFilter.all);
                    controller.setInstallationFilter(
                      MediaGalleryInstallationFilter.all,
                    );
                  },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final crossAxisCount = width >= 1500
                        ? 5
                        : width >= 1200
                        ? 4
                        : width >= 860
                        ? 3
                        : width >= 560
                        ? 2
                        : 1;
                    final childAspectRatio = width >= 1200
                        ? 0.78
                        : width >= 860
                        ? 0.8
                        : width >= 560
                        ? 0.82
                        : 0.92;

                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = visibleItems[index];
                        return MediaGalleryCard(
                          item: item,
                          onTap: () => showMediaGalleryViewer(context, item),
                        );
                      }, childCount: visibleItems.length),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        childAspectRatio: childAspectRatio,
                      ),
                    );
                  },
                ),
              ),
            if (state.loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if ((state.nextCursor ?? '').trim().isEmpty &&
                visibleItems.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Center(
                    child: Text(
                      'No hay más elementos para cargar.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryHero extends StatelessWidget {
  const _GalleryHero({
    required this.totalItems,
    required this.visibleItems,
    required this.completedCount,
    required this.pendingCount,
    required this.state,
    required this.onTypeChanged,
    required this.onInstallationChanged,
  });

  final int totalItems;
  final int visibleItems;
  final int completedCount;
  final int pendingCount;
  final MediaGalleryState state;
  final ValueChanged<MediaGalleryTypeFilter> onTypeChanged;
  final ValueChanged<MediaGalleryInstallationFilter> onInstallationChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 760;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF14532D), Color(0xFF164E63)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Catálogo de trabajos reales',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Carga desde caché local al instante y sincronización silenciosa en segundo plano para que marketing siempre tenga material listo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _HeroStat(label: 'Catálogo local', value: '$totalItems'),
                _HeroStat(label: 'Vista actual', value: '$visibleItems'),
                _HeroStat(label: 'Instalados', value: '$completedCount'),
                _HeroStat(label: 'Pendientes', value: '$pendingCount'),
              ],
            ),
            const SizedBox(height: 22),
            if (isCompact) ...[
              _FilterScroller(
                child: SegmentedButton<MediaGalleryTypeFilter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: MediaGalleryTypeFilter.all,
                      label: Text('Todos'),
                      icon: Icon(Icons.apps_outlined),
                    ),
                    ButtonSegment(
                      value: MediaGalleryTypeFilter.image,
                      label: Text('Imágenes'),
                      icon: Icon(Icons.image_outlined),
                    ),
                    ButtonSegment(
                      value: MediaGalleryTypeFilter.video,
                      label: Text('Videos'),
                      icon: Icon(Icons.play_circle_outline),
                    ),
                  ],
                  selected: {state.typeFilter},
                  onSelectionChanged: (value) => onTypeChanged(value.first),
                ),
              ),
              const SizedBox(height: 12),
              _FilterScroller(
                child: SegmentedButton<MediaGalleryInstallationFilter>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: MediaGalleryInstallationFilter.all,
                      label: Text('Todos'),
                    ),
                    ButtonSegment(
                      value: MediaGalleryInstallationFilter.completed,
                      label: Text('Instalados'),
                    ),
                    ButtonSegment(
                      value: MediaGalleryInstallationFilter.pending,
                      label: Text('Pendientes'),
                    ),
                  ],
                  selected: {state.installationFilter},
                  onSelectionChanged: (value) =>
                      onInstallationChanged(value.first),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _FilterScroller(
                      child: SegmentedButton<MediaGalleryTypeFilter>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: MediaGalleryTypeFilter.all,
                            label: Text('Todos'),
                            icon: Icon(Icons.apps_outlined),
                          ),
                          ButtonSegment(
                            value: MediaGalleryTypeFilter.image,
                            label: Text('Imágenes'),
                            icon: Icon(Icons.image_outlined),
                          ),
                          ButtonSegment(
                            value: MediaGalleryTypeFilter.video,
                            label: Text('Videos'),
                            icon: Icon(Icons.play_circle_outline),
                          ),
                        ],
                        selected: {state.typeFilter},
                        onSelectionChanged: (value) =>
                            onTypeChanged(value.first),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FilterScroller(
                      child: SegmentedButton<MediaGalleryInstallationFilter>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: MediaGalleryInstallationFilter.all,
                            label: Text('Todos'),
                          ),
                          ButtonSegment(
                            value: MediaGalleryInstallationFilter.completed,
                            label: Text('Instalados'),
                          ),
                          ButtonSegment(
                            value: MediaGalleryInstallationFilter.pending,
                            label: Text('Pendientes'),
                          ),
                        ],
                        selected: {state.installationFilter},
                        onSelectionChanged: (value) =>
                            onInstallationChanged(value.first),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 128),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterScroller extends StatelessWidget {
  const _FilterScroller({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Theme(
        data: Theme.of(context).copyWith(
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? const Color(0xFF052E16)
                    : Colors.white;
              }),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.selected)
                    ? const Color(0xFFFACC15)
                    : Colors.white.withValues(alpha: 0.1);
              }),
              side: WidgetStateProperty.all(
                BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _GalleryMessageState extends StatelessWidget {
  const _GalleryMessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: theme.colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}