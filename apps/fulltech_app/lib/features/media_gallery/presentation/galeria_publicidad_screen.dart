import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/utils/media_file_actions.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../data/media_gallery_repository.dart';
import '../media_gallery_models.dart';
import '../widgets/media_gallery_card.dart';

// ─── State & Controller ─────────────────────────────────────────────────────

class _GaleriaPublicidadState {
  const _GaleriaPublicidadState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<MediaGalleryItem> items;
  final bool loading;
  final String? error;

  _GaleriaPublicidadState copyWith({
    List<MediaGalleryItem>? items,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return _GaleriaPublicidadState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final _galeriaPublicidadControllerProvider = StateNotifierProvider.autoDispose<
    _GaleriaPublicidadController, _GaleriaPublicidadState>((ref) {
  return _GaleriaPublicidadController(ref);
});

class _GaleriaPublicidadController
    extends StateNotifier<_GaleriaPublicidadState> {
  _GaleriaPublicidadController(this._ref)
      : super(const _GaleriaPublicidadState()) {
    unawaited(load());
  }

  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items =
          await _ref.read(mediaGalleryRepositoryProvider).fetchPublicidad();
      state = state.copyWith(items: items, loading: false);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo cargar la galería de publicidad.',
      );
    }
  }

  Future<void> removeItem(String id) async {
    try {
      await _ref.read(mediaGalleryRepositoryProvider).unmarkForPublicidad(id);
      final updated =
          state.items.where((i) => i.id != id).toList(growable: false);
      state = state.copyWith(items: updated);
    } catch (error) {
      state = state.copyWith(
        error: 'No se pudo quitar el elemento de publicidad.',
      );
    }
  }
}

// ─── Screen ─────────────────────────────────────────────────────────────────

class GaleriaPublicidadScreen extends ConsumerStatefulWidget {
  const GaleriaPublicidadScreen({super.key});

  @override
  ConsumerState<GaleriaPublicidadScreen> createState() =>
      _GaleriaPublicidadScreenState();
}

class _GaleriaPublicidadScreenState
    extends ConsumerState<GaleriaPublicidadScreen> {
  String _searchQuery = '';

  List<MediaGalleryItem> _applySearch(List<MediaGalleryItem> items) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where((item) => item.searchableText.contains(q))
        .toList(growable: false);
  }

  Future<void> _downloadItem(MediaGalleryItem item) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final dio = ref.read(dioProvider);
      final bytes = await _downloadMediaBytes(dio, item.url);
      final extension = item.suggestedFileName.split('.').last.toLowerCase();
      final saved = await saveMediaBytes(
        bytes: bytes,
        fileName: item.suggestedFileName,
        allowedExtensions: [extension],
        mimeType: item.isVideo ? 'video/mp4' : 'image/jpeg',
      );
      if (!mounted || !saved) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${item.isVideo ? 'Video' : 'Imagen'} descargado correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo descargar el archivo: $error')),
      );
    }
  }

  Future<Uint8List> _downloadMediaBytes(Dio dio, String url) async {
    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          extra: const {'skipLoader': true, 'silent': true},
        ),
      );
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        return Uint8List.fromList(data);
      }
    } on DioException {
      // fall through to stream fallback
    }

    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        extra: const {'skipLoader': true, 'silent': true},
      ),
    );
    final body = response.data;
    if (body == null) throw Exception('El servidor no devolvió contenido');
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw Exception('El archivo llegó vacío');
    return bytes;
  }

  Future<void> _confirmRemove(MediaGalleryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar de publicidad'),
        content: const Text(
          '¿Deseas quitar esta evidencia de la Galería de Publicidad?\n'
          'La evidencia seguirá existiendo en la galería de medios.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref
        .read(_galeriaPublicidadControllerProvider.notifier)
        .removeItem(item.id);
    if (!mounted) return;
    messenger?.showSnackBar(
      const SnackBar(content: Text('Elemento quitado de publicidad.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final canView = auth.isAuthenticated &&
        auth.user != null &&
        hasPermission(auth.user!.appRole, AppPermission.viewGaleriaPublicidad);
    final state = ref.watch(_galeriaPublicidadControllerProvider);
    final controller =
        ref.read(_galeriaPublicidadControllerProvider.notifier);

    if (!canView) {
      return Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
        appBar: const CustomAppBar(
          title: 'Galería de Publicidad',
          showLogo: false,
          showDepartmentLabel: false,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta pantalla está disponible solo para administradores.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final visibleItems = _applySearch(state.items);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
      appBar: CustomAppBar(
        title: 'Galería de Publicidad',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar búsqueda',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _searchQuery = ''),
            ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search_rounded),
            onPressed: state.items.isEmpty
                ? null
                : () async {
                    final result = await showSearch<String?>(
                      context: context,
                      delegate: _PublicidadSearchDelegate(
                        items: state.items,
                        initialQuery: _searchQuery,
                      ),
                    );
                    if (!mounted || result == null) return;
                    setState(() => _searchQuery = result.trim());
                  },
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.loading ? null : () => controller.load(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.load(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Header info chip
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD8B4FE)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.campaign_rounded,
                            size: 16,
                            color: Color(0xFF7C3AED),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${visibleItems.length} elemento${visibleItems.length != 1 ? 's' : ''} para publicidad',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7C3AED),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Loading / Error / Empty / Grid states
            if (state.loading && state.items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if ((state.error ?? '').isNotEmpty && state.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'No se pudo cargar',
                  message: state.error!,
                  actionLabel: 'Reintentar',
                  onAction: () => controller.load(),
                ),
              )
            else if (visibleItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'Sin elementos de publicidad',
                  message: _searchQuery.trim().isNotEmpty
                      ? 'No hay coincidencias con la búsqueda.'
                      : 'Desde la Galería Media, un administrador puede marcar\nevidencias para que aparezcan aquí.',
                  actionLabel: _searchQuery.trim().isNotEmpty
                      ? 'Limpiar búsqueda'
                      : null,
                  onAction: _searchQuery.trim().isNotEmpty
                      ? () => setState(() => _searchQuery = '')
                      : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final crossAxisCount = width >= 1500
                        ? 5
                        : width >= 1200
                            ? 4
                            : width >= 860
                                ? 3
                                : 2;
                    final childAspectRatio = width >= 1200
                        ? 0.92
                        : width >= 860
                            ? 0.9
                            : width >= 420
                                ? 0.72
                                : 0.66;

                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = visibleItems[index];
                          return MediaGalleryCard(
                            item: item,
                            isAdmin: true,
                            onTap: () => showMediaGalleryViewer(
                              context,
                              visibleItems,
                              index,
                              _downloadItem,
                            ),
                            onDownload: () => _downloadItem(item),
                            onDelete: () => _confirmRemove(item),
                          );
                        },
                        childCount: visibleItems.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: childAspectRatio,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Search Delegate ─────────────────────────────────────────────────────────

class _PublicidadSearchDelegate extends SearchDelegate<String?> {
  _PublicidadSearchDelegate({required this.items, String initialQuery = ''}) {
    query = initialQuery;
  }

  final List<MediaGalleryItem> items;

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Limpiar',
          icon: const Icon(Icons.clear_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Regresar',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    close(context, query.trim());
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.trim().toLowerCase();
    final results =
        q.isEmpty ? items : items.where((i) => i.searchableText.contains(q)).toList();
    if (results.isEmpty) {
      return const Center(child: Text('Sin resultados'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: Text(item.displayComment),
          subtitle: Text('Orden: ${item.orderId.substring(0, 8)}...'),
          onTap: () => close(context, item.searchableText),
        );
      },
    );
  }
}

// ─── Empty / Error State ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF475569),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
