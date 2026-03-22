import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import 'application/service_orders_list_controller.dart';
import 'service_order_models.dart';

class ServiceOrdersListScreen extends ConsumerStatefulWidget {
  const ServiceOrdersListScreen({super.key});

  @override
  ConsumerState<ServiceOrdersListScreen> createState() =>
      _ServiceOrdersListScreenState();
}

class _ServiceOrdersListScreenState
    extends ConsumerState<ServiceOrdersListScreen> {
  ServiceOrdersFilter _filter = const ServiceOrdersFilter.today();
  final Set<String> _busyOrderIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceOrdersListControllerProvider);
    final controller = ref.read(serviceOrdersListControllerProvider.notifier);
    final currentUser = ref.watch(authStateProvider).user;
    final isAdmin = currentUser?.appRole.isAdmin ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopShellBreakpoint;
    final visibleOrders = _filter.apply(state.items);
    final contentMaxWidth = isDesktop ? 1100.0 : double.infinity;

    return Scaffold(
      drawer: isDesktop
          ? null
          : buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: AppBar(
        toolbarHeight: 54,
        centerTitle: true,
        leading: isDesktop
            ? null
            : Builder(
                builder: (context) {
                  return IconButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded),
                    tooltip: 'Menú',
                  );
                },
              ),
        title: const Text('Operaciones'),
        actions: [
          _ProfileAvatarButton(currentUser: currentUser),
          IconButton(
            onPressed: () async {
              final next = await showModalBottomSheet<ServiceOrdersFilter>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (sheetContext) {
                  return _FiltersSheet(initialFilter: _filter);
                },
              );
              if (next == null || !mounted) {
                return;
              }
              setState(() {
                _filter = next;
              });
            },
            icon: Icon(
              _filter.hasActiveFilters
                  ? Icons.filter_alt_rounded
                  : Icons.search_rounded,
            ),
            tooltip: 'Filtros',
          ),
          IconButton(
            onPressed: state.refreshing ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.7),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'service-orders-new-order',
        elevation: 2,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () async {
          final created = await context.push<bool>(Routes.serviceOrderCreate);
          if (created == true) {
            await controller.refresh();
            if (!context.mounted) return;
            await AppFeedback.showInfo(
              context,
              'Lista actualizada con la nueva orden',
            );
          }
        },
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Nueva orden'),
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && state.items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(state.error!, textAlign: TextAlign.center),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: visibleOrders.isEmpty ? 3 : visibleOrders.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentMaxWidth),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _OperationalHeader(
                                totalOrders: visibleOrders.length,
                                filterLabel: _filter.summaryLabel,
                              ),
                            ),
                          ),
                        );
                      }

                      if (index == 1) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentMaxWidth),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ActiveFiltersRow(
                                filter: _filter,
                                onClear: _filter.hasActiveFilters
                                    ? () {
                                        setState(() {
                                          _filter = const ServiceOrdersFilter.today();
                                        });
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        );
                      }

                      if (visibleOrders.isEmpty) {
                        return Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: contentMaxWidth),
                            child: const Padding(
                              padding: EdgeInsets.only(top: 28),
                              child: _EmptyOrdersState(),
                            ),
                          ),
                        );
                      }

                      final order = visibleOrders[index - 2];
                      final client = state.clientsById[order.clientId];
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentMaxWidth),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ServiceOrderListCard(
                              order: order,
                              clientName:
                                  client?.nombre ?? 'Cliente ${order.clientId}',
                              trailing: isAdmin
                                  ? _AdminOrderActions(
                                      order: order,
                                      busy: _busyOrderIds.contains(order.id),
                                      onEdit: () => _editOrder(order),
                                      onDelete: () => _deleteOrder(order),
                                    )
                                  : null,
                              onTap: () async {
                                final updated = await context.push<bool>(
                                  Routes.serviceOrderById(order.id),
                                );
                                if (updated == true) {
                                  await controller.refresh();
                                }
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Future<void> _editOrder(ServiceOrderModel order) async {
    final updated = await context.push<bool>(
      Routes.serviceOrderCreate,
      extra: ServiceOrderCreateArgs(editSource: order),
    );
    if (updated == true) {
      await ref.read(serviceOrdersListControllerProvider.notifier).refresh();
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Orden actualizada');
    }
  }

  Future<void> _deleteOrder(ServiceOrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar orden'),
          content: Text(
            'Esta acción eliminará la orden de ${order.category.label.toLowerCase()} para este cliente. No se puede deshacer.',
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

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busyOrderIds.add(order.id);
    });

    try {
      await ref.read(serviceOrdersListControllerProvider.notifier).deleteOrder(
            order.id,
          );
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Orden eliminada');
    } catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error is ApiException
            ? error.message
            : 'No se pudo eliminar la orden',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOrderIds.remove(order.id);
        });
      }
    }
  }
}

enum ServiceOrdersDatePreset { today, thisWeek, custom }

class ServiceOrdersFilter {
  const ServiceOrdersFilter({
    required this.datePreset,
    this.statuses = const <ServiceOrderStatus>{},
    this.categories = const <ServiceOrderCategory>{},
    this.customRange,
  });

  const ServiceOrdersFilter.today()
      : datePreset = ServiceOrdersDatePreset.today,
        statuses = const <ServiceOrderStatus>{},
        categories = const <ServiceOrderCategory>{},
        customRange = null;

  final ServiceOrdersDatePreset datePreset;
  final Set<ServiceOrderStatus> statuses;
  final Set<ServiceOrderCategory> categories;
  final DateTimeRange? customRange;

  bool get hasActiveFilters {
    return statuses.isNotEmpty ||
        categories.isNotEmpty ||
        datePreset != ServiceOrdersDatePreset.today;
  }

  String get summaryLabel {
    switch (datePreset) {
      case ServiceOrdersDatePreset.today:
        return 'Hoy';
      case ServiceOrdersDatePreset.thisWeek:
        return 'Esta semana';
      case ServiceOrdersDatePreset.custom:
        if (customRange == null) return 'Personalizado';
        final formatter = DateFormat('dd MMM', 'es_DO');
        return '${formatter.format(customRange!.start)} - ${formatter.format(customRange!.end)}';
    }
  }

  List<String> get activeChips {
    final chips = <String>[summaryLabel];
    chips.addAll(statuses.map((status) => status.label));
    chips.addAll(categories.map((category) => category.label));
    return chips;
  }

  List<ServiceOrderModel> apply(List<ServiceOrderModel> source) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final weekEnd = weekStart.add(const Duration(days: 7));
    final customStart = customRange == null
        ? null
        : DateTime(
            customRange!.start.year,
            customRange!.start.month,
            customRange!.start.day,
          );
    final customEnd = customRange == null
        ? null
        : DateTime(
            customRange!.end.year,
            customRange!.end.month,
            customRange!.end.day,
          ).add(const Duration(days: 1));

    return source.where((order) {
      final createdAt = order.createdAt.toLocal();
      final matchesDate = switch (datePreset) {
        ServiceOrdersDatePreset.today =>
          !createdAt.isBefore(todayStart) && createdAt.isBefore(todayEnd),
        ServiceOrdersDatePreset.thisWeek =>
          !createdAt.isBefore(weekStart) && createdAt.isBefore(weekEnd),
        ServiceOrdersDatePreset.custom =>
          customStart != null &&
              customEnd != null &&
              !createdAt.isBefore(customStart) &&
              createdAt.isBefore(customEnd),
      };

      if (!matchesDate) {
        return false;
      }
      if (statuses.isNotEmpty && !statuses.contains(order.status)) {
        return false;
      }
      if (categories.isNotEmpty && !categories.contains(order.category)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
}

class _ProfileAvatarButton extends ConsumerWidget {
  const _ProfileAvatarButton({required this.currentUser});

  final UserModel? currentUser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl = currentUser?.fotoPersonalUrl;
    final name = currentUser?.nombreCompleto ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => context.push(Routes.profile),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          backgroundImage:
              (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
          child: (photoUrl == null || photoUrl.isEmpty)
              ? Text(
                  initial,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initialFilter});

  final ServiceOrdersFilter initialFilter;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late Set<ServiceOrderStatus> _statuses;
  late Set<ServiceOrderCategory> _categories;
  late ServiceOrdersDatePreset _datePreset;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _statuses = {...widget.initialFilter.statuses};
    _categories = {...widget.initialFilter.categories};
    _datePreset = widget.initialFilter.datePreset;
    _customRange = widget.initialFilter.customRange;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Filtros',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ajusta la vista operativa sin recargar la pantalla.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              _FilterSection(
                title: 'Estado',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrderStatus.values.map((status) {
                    final selected = _statuses.contains(status);
                    return FilterChip(
                      selected: selected,
                      label: Text(status.label),
                      selectedColor: status.color.withValues(alpha: 0.12),
                      side: BorderSide(
                        color: selected
                            ? status.color.withValues(alpha: 0.35)
                            : theme.colorScheme.outlineVariant,
                      ),
                      labelStyle: TextStyle(
                        color: selected ? status.color : null,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      onSelected: (_) {
                        setState(() {
                          if (selected) {
                            _statuses.remove(status);
                          } else {
                            _statuses.add(status);
                          }
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
              ),
              const SizedBox(height: 16),
              _FilterSection(
                title: 'Categoría',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrderCategory.values.map((category) {
                    final selected = _categories.contains(category);
                    return FilterChip(
                      selected: selected,
                      label: Text(category.label),
                      onSelected: (_) {
                        setState(() {
                          if (selected) {
                            _categories.remove(category);
                          } else {
                            _categories.add(category);
                          }
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
              ),
              const SizedBox(height: 16),
              _FilterSection(
                title: 'Rango de fecha',
                child: Column(
                  children: [
                    RadioListTile<ServiceOrdersDatePreset>(
                      value: ServiceOrdersDatePreset.today,
                      groupValue: _datePreset,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Hoy'),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _datePreset = value;
                        });
                      },
                    ),
                    RadioListTile<ServiceOrdersDatePreset>(
                      value: ServiceOrdersDatePreset.thisWeek,
                      groupValue: _datePreset,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Esta semana'),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _datePreset = value;
                        });
                      },
                    ),
                    RadioListTile<ServiceOrdersDatePreset>(
                      value: ServiceOrdersDatePreset.custom,
                      groupValue: _datePreset,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Personalizado'),
                      subtitle: _customRange == null
                          ? const Text('Selecciona un rango')
                          : Text(
                              '${DateFormat('dd/MM/yyyy').format(_customRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_customRange!.end)}',
                            ),
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() {
                          _datePreset = value;
                        });
                        await _pickCustomRange();
                      },
                    ),
                    if (_datePreset == ServiceOrdersDatePreset.custom)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _pickCustomRange,
                          icon: const Icon(Icons.date_range_outlined),
                          label: const Text('Elegir rango'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(const ServiceOrdersFilter.today());
                      },
                      child: const Text('Restablecer'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final effectivePreset = _datePreset ==
                                    ServiceOrdersDatePreset.custom &&
                                _customRange == null
                            ? ServiceOrdersDatePreset.today
                            : _datePreset;
                        Navigator.of(context).pop(
                          ServiceOrdersFilter(
                            datePreset: effectivePreset,
                            statuses: _statuses,
                            categories: _categories,
                            customRange: effectivePreset ==
                                    ServiceOrdersDatePreset.custom
                                ? _customRange
                                : null,
                          ),
                        );
                      },
                      child: const Text('Aplicar filtros'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
      helpText: 'Selecciona el rango',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customRange = picked;
      _datePreset = ServiceOrdersDatePreset.custom;
    });
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _OperationalHeader extends StatelessWidget {
  const _OperationalHeader({
    required this.totalOrders,
    required this.filterLabel,
  });

  final int totalOrders;
  final String filterLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF11304A), Color(0xFF27667B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Control operativo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalOrders órdenes · $filterLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.assignment_turned_in_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFiltersRow extends StatelessWidget {
  const _ActiveFiltersRow({required this.filter, required this.onClear});

  final ServiceOrdersFilter filter;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...filter.activeChips.map(
          (chip) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              chip,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        if (onClear != null)
          TextButton(
            onPressed: onClear,
            child: const Text('Limpiar'),
          ),
      ],
    );
  }
}

class _ServiceOrderListCard extends StatelessWidget {
  const _ServiceOrderListCard({
    required this.order,
    required this.clientName,
    required this.onTap,
    this.trailing,
  });

  final ServiceOrderModel order;
  final String clientName;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _CompactInfoChip(
                            icon: Icons.category_outlined,
                            text: order.category.label,
                          ),
                          _CompactInfoChip(
                            icon: Icons.build_circle_outlined,
                            text: order.serviceType.label,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat(
                          'dd/MM/yyyy · h:mm a',
                          'es_DO',
                        ).format(order.createdAt.toLocal()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (trailing != null) trailing!,
                    if (trailing != null) const SizedBox(height: 8),
                    _StatusBadge(status: order.status),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminOrderActions extends StatelessWidget {
  const _AdminOrderActions({
    required this.order,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final ServiceOrderModel order;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: !busy,
      tooltip: 'Acciones de administrador',
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined),
            title: Text('Editar'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.delete_outline),
            title: Text('Eliminar'),
          ),
        ),
      ],
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert_rounded),
    );
  }
}

class _CompactInfoChip extends StatelessWidget {
  const _CompactInfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ServiceOrderStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.22)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 30,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'No hay órdenes para los filtros actuales',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Prueba otro estado, categoría o rango de fecha para ver más resultados.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}