import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/sync_status_banner.dart';
import 'application/clientes_controller.dart';
import 'cliente_model.dart';
import 'data/clientes_repository.dart';

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key});

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _purgingAllDebug = false;

  Future<void> _openFilters(ClientesState state) async {
    final next = await showModalBottomSheet<_ClientesFilterState>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _ClientesFiltersSheet(
          initialState: _ClientesFilterState(
            order: state.order,
            correoFilter: state.correoFilter,
            estadoFilter: state.estadoFilter,
          ),
        );
      },
    );

    if (next == null || !mounted) return;

    await ref
        .read(clientesControllerProvider.notifier)
        .applyFilters(
          order: next.order,
          correoFilter: next.correoFilter,
          estadoFilter: next.estadoFilter,
        );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(clientesControllerProvider.notifier).load(search: value);
    });
  }

  Future<void> _purgeAllDebug() async {
    final confirmed = await confirmDebugAdminPurge(
      context,
      moduleLabel: 'clientes',
      impactLabel: 'todos los clientes y sus datos relacionados',
    );
    if (!confirmed || !mounted) return;

    setState(() => _purgingAllDebug = true);
    try {
      final deleted = await ref
          .read(clientesControllerProvider.notifier)
          .purgeAllDebug();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Se limpiaron $deleted clientes.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        setState(() => _purgingAllDebug = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final state = ref.watch(clientesControllerProvider);
    final controller = ref.read(clientesControllerProvider.notifier);
    final theme = Theme.of(context);
    final activeFilterCount = [
      state.order != ClientesOrder.az,
      state.correoFilter != CorreoFilter.todos,
      state.estadoFilter != EstadoFilter.activos,
    ].where((active) => active).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
              child: _ClientesTopPanel(
                searchController: _searchCtrl,
                refreshing: state.refreshing,
                purgingAllDebug: _purgingAllDebug,
                activeFilterCount: activeFilterCount,
                canShowDebugAction: canUseDebugAdminAction(currentUser),
                onBack: () => AppNavigator.goBack(
                  context,
                  fallbackRoute: Routes.home,
                ),
                onSearchChanged: _handleSearch,
                onOpenMap: () => context.push(Routes.clientesMapa),
                onOpenFilters: () => _openFilters(state),
                onMenuActionSelected: (action) async {
                  switch (action) {
                    case _ClientesTopAction.newClient:
                      context.push(Routes.clienteNuevo);
                      break;
                    case _ClientesTopAction.refresh:
                      if (!state.refreshing) {
                        await controller.refresh();
                      }
                      break;
                    case _ClientesTopAction.clearFilters:
                      await controller.applyFilters(
                        order: ClientesOrder.az,
                        correoFilter: CorreoFilter.todos,
                        estadoFilter: EstadoFilter.activos,
                      );
                      break;
                    case _ClientesTopAction.purgeDebug:
                      if (!_purgingAllDebug) {
                        await _purgeAllDebug();
                      }
                      break;
                  }
                },
                showClearFiltersAction: activeFilterCount > 0,
              ),
            ),
            SyncStatusBanner(
              visible: state.refreshing,
              label: 'Sincronizando clientes...',
            ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: Material(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: controller.refresh,
                      child: state.items.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Text('No hay clientes disponibles.'),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                              itemCount: state.items.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                              itemBuilder: (context, index) {
                                final client = state.items[index];
                                return _ClienteCard(client: client);
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClienteCard extends ConsumerWidget {
  const _ClienteCard({required this.client});

  final ClienteModel client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final phone = client.telefono.trim();
    final createdAt = client.createdAt == null
        ? null
        : _formatClientDate(client.createdAt!);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push(Routes.clienteDetail(client.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            client.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                          ),
                        ),
                        if (client.isDeleted)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'Eliminado',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            phone.isEmpty ? 'Sin telefono' : phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (createdAt != null)
                          Text(
                            createdAt,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ClientesTopAction { newClient, refresh, clearFilters, purgeDebug }

class _ClientesTopPanel extends StatelessWidget {
  const _ClientesTopPanel({
    required this.searchController,
    required this.refreshing,
    required this.purgingAllDebug,
    required this.activeFilterCount,
    required this.canShowDebugAction,
    required this.onBack,
    required this.onSearchChanged,
    required this.onOpenMap,
    required this.onOpenFilters,
    required this.onMenuActionSelected,
    required this.showClearFiltersAction,
  });

  final TextEditingController searchController;
  final bool refreshing;
  final bool purgingAllDebug;
  final int activeFilterCount;
  final bool canShowDebugAction;
  final VoidCallback onBack;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenFilters;
  final ValueChanged<_ClientesTopAction> onMenuActionSelected;
  final bool showClearFiltersAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                _TopCircleButton(
                  tooltip: 'Regresar',
                  icon: Icons.arrow_back_rounded,
                  onPressed: onBack,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Clientes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _TopCircleButton(
                  tooltip: 'Mapa',
                  icon: Icons.map_outlined,
                  onPressed: onOpenMap,
                ),
                const SizedBox(width: 6),
                PopupMenuButton<_ClientesTopAction>(
                  tooltip: 'Opciones',
                  onSelected: onMenuActionSelected,
                  itemBuilder: (context) => [
                    _topMenuItem(
                      context,
                      value: _ClientesTopAction.newClient,
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Nuevo cliente',
                    ),
                    _topMenuItem(
                      context,
                      value: _ClientesTopAction.refresh,
                      icon: Icons.refresh_rounded,
                      label: refreshing ? 'Actualizando...' : 'Actualizar',
                      enabled: !refreshing,
                    ),
                    if (showClearFiltersAction)
                      _topMenuItem(
                        context,
                        value: _ClientesTopAction.clearFilters,
                        icon: Icons.filter_alt_off_rounded,
                        label: 'Limpiar filtros',
                      ),
                    if (canShowDebugAction)
                      _topMenuItem(
                        context,
                        value: _ClientesTopAction.purgeDebug,
                        icon: Icons.delete_sweep_rounded,
                        label: purgingAllDebug
                            ? 'Limpiando tabla...'
                            : 'Limpiar tabla (debug)',
                        enabled: !purgingAllDebug,
                      ),
                  ],
                  child: const _TopCircleButton(
                    tooltip: 'Opciones',
                    icon: Icons.more_vert_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Buscar clientes',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _SearchFilterButton(
                  tooltip: 'Filtros',
                  badgeCount: activeFilterCount,
                  onPressed: onOpenFilters,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

PopupMenuItem<_ClientesTopAction> _topMenuItem(
  BuildContext context, {
  required _ClientesTopAction value,
  required IconData icon,
  required String label,
  bool enabled = true,
}) {
  final theme = Theme.of(context);
  return PopupMenuItem<_ClientesTopAction>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatClientDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

class _SearchFilterButton extends StatelessWidget {
  const _SearchFilterButton({
    required this.tooltip,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Tooltip(
                message: tooltip,
                child: Icon(
                  Icons.tune_rounded,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$badgeCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ClientesFilterState {
  const _ClientesFilterState({
    required this.order,
    required this.correoFilter,
    required this.estadoFilter,
  });

  final ClientesOrder order;
  final CorreoFilter correoFilter;
  final EstadoFilter estadoFilter;

  _ClientesFilterState copyWith({
    ClientesOrder? order,
    CorreoFilter? correoFilter,
    EstadoFilter? estadoFilter,
  }) {
    return _ClientesFilterState(
      order: order ?? this.order,
      correoFilter: correoFilter ?? this.correoFilter,
      estadoFilter: estadoFilter ?? this.estadoFilter,
    );
  }
}

class _ClientesFiltersSheet extends StatefulWidget {
  const _ClientesFiltersSheet({required this.initialState});

  final _ClientesFilterState initialState;

  @override
  State<_ClientesFiltersSheet> createState() => _ClientesFiltersSheetState();
}

class _ClientesFiltersSheetState extends State<_ClientesFiltersSheet> {
  late _ClientesFilterState _draft = widget.initialState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtros de clientes',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Organiza la lista y el mapa con el mismo criterio de consulta.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _FilterSection<ClientesOrder>(
              title: 'Orden',
              value: _draft.order,
              options: const [ClientesOrder.az, ClientesOrder.za],
              labelBuilder: _clientesOrderLabel,
              onSelected: (value) {
                setState(() => _draft = _draft.copyWith(order: value));
              },
            ),
            const SizedBox(height: 16),
            _FilterSection<CorreoFilter>(
              title: 'Correo',
              value: _draft.correoFilter,
              options: const [
                CorreoFilter.todos,
                CorreoFilter.conCorreo,
                CorreoFilter.sinCorreo,
              ],
              labelBuilder: _correoFilterLabel,
              onSelected: (value) {
                setState(() => _draft = _draft.copyWith(correoFilter: value));
              },
            ),
            const SizedBox(height: 16),
            _FilterSection<EstadoFilter>(
              title: 'Estado',
              value: _draft.estadoFilter,
              options: const [
                EstadoFilter.activos,
                EstadoFilter.eliminados,
                EstadoFilter.todos,
              ],
              labelBuilder: _estadoFilterLabel,
              onSelected: (value) {
                setState(() => _draft = _draft.copyWith(estadoFilter: value));
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      const _ClientesFilterState(
                        order: ClientesOrder.az,
                        correoFilter: CorreoFilter.todos,
                        estadoFilter: EstadoFilter.activos,
                      ),
                    );
                  },
                  child: const Text('Limpiar'),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection<T> extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String title;
  final T value;
  final List<T> options;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            for (var index = 0; index < options.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              Material(
                color: optionEquals(options[index], value)
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.25,
                      ),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onSelected(options[index]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          optionEquals(options[index], value)
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 18,
                          color: optionEquals(options[index], value)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            labelBuilder(options[index]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: optionEquals(options[index], value)
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  bool optionEquals(T left, T right) => left == right;
}

String _clientesOrderLabel(ClientesOrder order) {
  switch (order) {
    case ClientesOrder.az:
      return 'Nombre A-Z';
    case ClientesOrder.za:
      return 'Nombre Z-A';
  }
}

String _correoFilterLabel(CorreoFilter filter) {
  switch (filter) {
    case CorreoFilter.todos:
      return 'Todos';
    case CorreoFilter.conCorreo:
      return 'Con correo';
    case CorreoFilter.sinCorreo:
      return 'Sin correo';
  }
}

String _estadoFilterLabel(EstadoFilter filter) {
  switch (filter) {
    case EstadoFilter.activos:
      return 'Activos';
    case EstadoFilter.eliminados:
      return 'Eliminados';
    case EstadoFilter.todos:
      return 'Todos';
  }
}
