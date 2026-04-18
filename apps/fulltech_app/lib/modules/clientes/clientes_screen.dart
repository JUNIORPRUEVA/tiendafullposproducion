import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
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
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: CustomAppBar(
        title: 'Clientes',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
              ),
              onPressed: () => context.push(Routes.clientesMapa),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Mapa'),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: state.refreshing ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          DebugAdminActionButton(
            user: currentUser,
            busy: _purgingAllDebug,
            tooltip: 'Limpiar tabla (debug)',
            onPressed: _purgeAllDebug,
          ),
          IconButton(
            tooltip: 'Nuevo cliente',
            onPressed: () => context.push(Routes.clienteNuevo),
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SyncStatusBanner(
            visible: state.refreshing,
            label: 'Sincronizando clientes...',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _handleSearch,
                    decoration: InputDecoration(
                      labelText: 'Buscar cliente',
                      hintText: 'Nombre, teléfono o correo',
                      prefixIcon: const Icon(Icons.search_rounded),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _SearchFilterButton(
                  tooltip: 'Filtros',
                  badgeCount: activeFilterCount,
                  onPressed: () => _openFilters(state),
                ),
              ],
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text('No hay clientes disponibles.'),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            itemCount: state.items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final client = state.items[index];
                              return _ClienteCard(client: client);
                            },
                          ),
                  ),
          ),
        ],
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
    final subtitle = _buildCompactSubtitle(client);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(Routes.clienteDetail(client.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              _InlineIconBtn(
                icon: Icons.edit_outlined,
                color: theme.colorScheme.primary,
                onPressed: () => context.push(Routes.clienteEdit(client.id)),
              ),
              _InlineIconBtn(
                icon: Icons.delete_outline_rounded,
                color: theme.colorScheme.error.withValues(alpha: 0.75),
                onPressed: () => _confirmDelete(context, ref, client),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineIconBtn extends StatelessWidget {
  const _InlineIconBtn({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.38,
        ),
        borderRadius: BorderRadius.circular(10),
        child: IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 17, color: color),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

String _buildCompactSubtitle(ClienteModel client) {
  final parts = <String>[client.telefono.trim()];

  if (client.createdAt != null) {
    parts.add('Creado ${_formatClientDate(client.createdAt!)}');
  }
  if (client.updatedLocal) {
    parts.add('Pendiente de sincronizar');
  } else if ((client.syncStatus ?? '').trim().isNotEmpty) {
    parts.add(client.syncStatus!.trim());
  }
  if (client.isDeleted) {
    parts.add('Eliminado');
  }

  return parts.where((item) => item.isNotEmpty).join(' • ');
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  ClienteModel client,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          'Se eliminara ${client.nombre}. Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) return;

  try {
    await ref.read(clientesControllerProvider.notifier).remove(client.id);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error.toString())));
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
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.6,
          ),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: SizedBox(
              width: 52,
              height: 52,
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
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(labelBuilder(option)),
                selected: option == value,
                onSelected: (_) => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
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
