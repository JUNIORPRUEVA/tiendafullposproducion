import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/realtime/operations_realtime_service.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../clientes/cliente_model.dart';
import '../clientes/client_location_utils.dart';
import 'application/service_orders_list_controller.dart';
import 'data/service_orders_api.dart';
import 'service_order_models.dart';
import 'widgets/client_location_card.dart';
import 'widgets/service_order_quick_actions_modal.dart';

class ServiceOrdersListScreen extends ConsumerStatefulWidget {
  const ServiceOrdersListScreen({super.key});

  @override
  ConsumerState<ServiceOrdersListScreen> createState() =>
      _ServiceOrdersListScreenState();
}

class _ServiceOrdersListScreenState
    extends ConsumerState<ServiceOrdersListScreen> {
  ServiceOrdersFilter _filter = const ServiceOrdersFilter.mainDefault();
  final Set<String> _busyOrderIds = <String>{};
  final Set<String> _creatingFromOrderIds = <String>{};
  StreamSubscription<OperationsRealtimeMessage>? _operationsRealtimeSubscription;

  @override
  void initState() {
    super.initState();
    _operationsRealtimeSubscription = ref
        .read(operationsRealtimeServiceProvider)
        .stream
        .listen(_handleRealtimeMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(serviceOrdersListControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _operationsRealtimeSubscription?.cancel();
    super.dispose();
  }

  void _handleRealtimeMessage(OperationsRealtimeMessage message) {
    if (!mounted) return;
    final controller = ref.read(serviceOrdersListControllerProvider.notifier);
    if (message.type == 'service.deleted') {
      unawaited(controller.refresh());
      return;
    }

    final payload = message.service;
    if (payload == null) {
      unawaited(controller.refresh());
      return;
    }

    try {
      controller.upsertOrder(ServiceOrderModel.fromJson(payload));
    } catch (_) {
      unawaited(controller.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceOrdersListControllerProvider);
    final controller = ref.read(serviceOrdersListControllerProvider.notifier);
    final currentUser = ref.watch(authStateProvider).user;
    final canManageStatus =
        currentUser?.appRole.isAdmin == true ||
        currentUser?.appRole.isTechnician == true;
    final isAdmin = currentUser?.appRole.isAdmin ?? false;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopShellBreakpoint;
    final visibleOrders = _filter.apply(state.items);
    final contentMaxWidth = isDesktop ? 1100.0 : double.infinity;

    return Scaffold(
      drawer: isDesktop
          ? null
          : buildAdaptiveDrawer(context, currentUser: currentUser),
      floatingActionButton: _CreateOrderFab(
        onPressed: _createOrder,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        toolbarHeight: 54,
        centerTitle: false,
        titleSpacing: isDesktop ? 16 : 0,
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
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 30,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            state.error!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: state.refreshing
                                ? null
                                : controller.retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                itemCount: visibleOrders.isEmpty ? 2 : visibleOrders.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: contentMaxWidth),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _OperationsControlPanel(
                            filter: _filter,
                            activeCount: visibleOrders.length,
                            onReset: _filter.hasActiveFilters
                                ? () {
                                    setState(() {
                                      _filter =
                                          const ServiceOrdersFilter.mainDefault();
                                    });
                                  }
                                : null,
                            onToggleStatus: (status) {
                              setState(() {
                                final nextStatuses = {..._filter.statuses};
                                if (nextStatuses.contains(status)) {
                                  nextStatuses.remove(status);
                                } else {
                                  nextStatuses.add(status);
                                }
                                _filter = _filter.copyWith(
                                  statuses: nextStatuses,
                                );
                              });
                            },
                            onToggleServiceType: (serviceType) {
                              setState(() {
                                final nextTypes = {..._filter.serviceTypes};
                                if (nextTypes.contains(serviceType)) {
                                  nextTypes.remove(serviceType);
                                } else {
                                  nextTypes.add(serviceType);
                                }
                                _filter = _filter.copyWith(
                                  serviceTypes: nextTypes,
                                );
                              });
                            },
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

                  final order = visibleOrders[index - 1];
                  final client = order.client ?? state.clientsById[order.clientId];
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMaxWidth),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ServiceOrderListCard(
                          order: order,
                          client: client,
                          clientName:
                              client?.nombre ?? 'Cliente ${order.clientId}',
                          creatorName:
                            state.usersById[order.createdById]?.nombreCompleto ??
                            order.createdById,
                          statusBusy: _busyOrderIds.contains(order.id),
                          isTechnician: currentUser?.appRole.isTechnician ?? false,
                          onChangeStatus: canManageStatus
                              ? (status) => _changeOrderStatus(order, status)
                              : null,
                          creatingNewOrder: _creatingFromOrderIds.contains(
                            order.id,
                          ),
                          onCreateNewOrder: order.isCloneSourceAllowed
                              ? () => _createOrderFromSource(order)
                              : null,
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

  Future<void> _createOrderFromSource(ServiceOrderModel order) async {
    if (_creatingFromOrderIds.contains(order.id)) {
      return;
    }

    setState(() {
      _creatingFromOrderIds.add(order.id);
    });

    try {
      final created = await context.push<bool>(
        Routes.serviceOrderCreate,
        extra: ServiceOrderCreateArgs(cloneSource: order),
      );
      if (created == true) {
        await ref.read(serviceOrdersListControllerProvider.notifier).refresh();
        if (!mounted) return;
        await AppFeedback.showInfo(context, 'Nueva orden creada');
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingFromOrderIds.remove(order.id);
        });
      }
    }
  }

  Future<void> _createOrder() async {
    final created = await context.push<bool>(Routes.serviceOrderCreate);
    if (created == true) {
      await ref.read(serviceOrdersListControllerProvider.notifier).refresh();
      if (!mounted) return;
      await AppFeedback.showInfo(
        context,
        'Lista actualizada con la nueva orden',
      );
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
      await ref
          .read(serviceOrdersListControllerProvider.notifier)
          .deleteOrder(order.id);
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Orden eliminada');
    } catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error is ApiException ? error.message : 'No se pudo eliminar la orden',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOrderIds.remove(order.id);
        });
      }
    }
  }

  Future<void> _changeOrderStatus(
    ServiceOrderModel order,
    ServiceOrderStatus status,
  ) async {
    if (_busyOrderIds.contains(order.id) || status == order.status) {
      return;
    }

    final previousOrder = order;
    setState(() {
      _busyOrderIds.add(order.id);
    });
    ref
        .read(serviceOrdersListControllerProvider.notifier)
        .replaceOrderStatus(orderId: order.id, status: status);

    try {
      final updated = await ref
          .read(serviceOrdersApiProvider)
          .updateStatus(order.id, status);
      ref.read(serviceOrdersListControllerProvider.notifier).upsertOrder(updated);
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Estado actualizado');
    } catch (error) {
      ref.read(serviceOrdersListControllerProvider.notifier).upsertOrder(previousOrder);
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error is ApiException ? error.message : 'No se pudo actualizar el estado',
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

enum ServiceOrdersDatePreset { all, today, thisWeek, custom }

class ServiceOrdersFilter {
  const ServiceOrdersFilter({
    required this.datePreset,
    this.statuses = const <ServiceOrderStatus>{},
    this.serviceTypes = const <ServiceOrderType>{},
    this.customRange,
  });

  const ServiceOrdersFilter.today()
    : datePreset = ServiceOrdersDatePreset.today,
      statuses = const <ServiceOrderStatus>{},
      serviceTypes = const <ServiceOrderType>{},
      customRange = null;

  const ServiceOrdersFilter.mainDefault()
    : datePreset = ServiceOrdersDatePreset.all,
      statuses = const <ServiceOrderStatus>{
        ServiceOrderStatus.pendiente,
        ServiceOrderStatus.enProceso,
        ServiceOrderStatus.cancelado,
      },
      serviceTypes = const <ServiceOrderType>{},
      customRange = null;

  final ServiceOrdersDatePreset datePreset;
  final Set<ServiceOrderStatus> statuses;
  final Set<ServiceOrderType> serviceTypes;
  final DateTimeRange? customRange;

  bool get isMainDefault {
    return datePreset == ServiceOrdersDatePreset.all &&
        serviceTypes.isEmpty &&
        statuses.length == 3 &&
        statuses.contains(ServiceOrderStatus.pendiente) &&
        statuses.contains(ServiceOrderStatus.enProceso) &&
        statuses.contains(ServiceOrderStatus.cancelado);
  }

  ServiceOrdersFilter copyWith({
    ServiceOrdersDatePreset? datePreset,
    Set<ServiceOrderStatus>? statuses,
    Set<ServiceOrderType>? serviceTypes,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
  }) {
    return ServiceOrdersFilter(
      datePreset: datePreset ?? this.datePreset,
      statuses: statuses ?? this.statuses,
      serviceTypes: serviceTypes ?? this.serviceTypes,
      customRange: clearCustomRange ? null : (customRange ?? this.customRange),
    );
  }

  bool get hasActiveFilters {
    return !isMainDefault;
  }

  String get summaryLabel {
    switch (datePreset) {
      case ServiceOrdersDatePreset.all:
        return 'Órdenes activas';
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
    chips.addAll(serviceTypes.map((serviceType) => serviceType.label));
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

    return source
        .where((order) {
          final createdAt = order.createdAt.toLocal();
          final matchesDate = switch (datePreset) {
            ServiceOrdersDatePreset.all => true,
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
          if (serviceTypes.isNotEmpty &&
              !serviceTypes.contains(order.serviceType)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
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
          backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
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
  late Set<ServiceOrderType> _serviceTypes;
  late ServiceOrdersDatePreset _datePreset;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _statuses = {...widget.initialFilter.statuses};
    _serviceTypes = {...widget.initialFilter.serviceTypes};
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
                  children: ServiceOrderStatus.values
                      .map((status) {
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
                      })
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 16),
              _FilterSection(
                title: 'Tipo de servicio',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrderType.values
                      .map((serviceType) {
                        final selected = _serviceTypes.contains(serviceType);
                        return FilterChip(
                          selected: selected,
                          label: Text(serviceType.label),
                          onSelected: (_) {
                            setState(() {
                              if (selected) {
                                _serviceTypes.remove(serviceType);
                              } else {
                                _serviceTypes.add(serviceType);
                              }
                            });
                          },
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 16),
              _FilterSection(
                title: 'Rango de fecha',
                child: Column(
                  children: [
                    RadioListTile<ServiceOrdersDatePreset>(
                      value: ServiceOrdersDatePreset.all,
                      groupValue: _datePreset,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Todas las fechas'),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _datePreset = value;
                        });
                      },
                    ),
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
                        ).pop(const ServiceOrdersFilter.mainDefault());
                      },
                      child: const Text('Restablecer'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final effectivePreset =
                            _datePreset == ServiceOrdersDatePreset.custom &&
                                _customRange == null
                          ? ServiceOrdersDatePreset.all
                            : _datePreset;
                        Navigator.of(context).pop(
                          ServiceOrdersFilter(
                            datePreset: effectivePreset,
                            statuses: _statuses,
                            serviceTypes: _serviceTypes,
                            customRange:
                                effectivePreset ==
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
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _OperationsControlPanel extends StatelessWidget {
  const _OperationsControlPanel({
    required this.filter,
    required this.activeCount,
    required this.onToggleStatus,
    required this.onToggleServiceType,
    required this.onReset,
  });

  final ServiceOrdersFilter filter;
  final int activeCount;
  final ValueChanged<ServiceOrderStatus> onToggleStatus;
  final ValueChanged<ServiceOrderType> onToggleServiceType;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE d MMM', 'es_DO').format(now);
    final timeLabel = DateFormat('h:mm a', 'es_DO').format(now);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.surfaceContainerLowest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _PanelMetaPill(
                          icon: Icons.dashboard_customize_rounded,
                          text: filter.summaryLabel,
                          accent: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        _PanelMetaPill(
                          icon: Icons.calendar_today_outlined,
                          text: _capitalize(dateLabel),
                        ),
                        const SizedBox(width: 6),
                        _PanelMetaPill(
                          icon: Icons.schedule_rounded,
                          text: timeLabel,
                        ),
                        const SizedBox(width: 6),
                        _PanelMetaPill(
                          icon: Icons.layers_outlined,
                          text: '$activeCount activas',
                        ),
                      ],
                    ),
                  ),
                ),
                if (onReset != null)
                  IconButton(
                    tooltip: 'Limpiar filtros',
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    onPressed: onReset,
                    icon: Icon(
                      Icons.restart_alt_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 19,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _CompactFilterLine<ServiceOrderStatus>(
              label: '',
              items: ServiceOrderStatus.values,
              isSelected: filter.statuses.contains,
              onToggle: onToggleStatus,
              labelBuilder: (status) => status.label,
              colorBuilder: (status) => status.color,
              centered: isDesktop,
            ),
            const SizedBox(height: 6),
            _CompactFilterLine<ServiceOrderType>(
              label: '',
              items: ServiceOrderType.values,
              isSelected: filter.serviceTypes.contains,
              onToggle: onToggleServiceType,
              labelBuilder: (serviceType) => serviceType.label,
              centered: isDesktop,
            ),
          ],
        ),
      ),
    );
  }
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

class _CompactFilterLine<T> extends StatelessWidget {
  const _CompactFilterLine({
    required this.label,
    required this.items,
    required this.isSelected,
    required this.onToggle,
    required this.labelBuilder,
    this.centered = false,
    this.colorBuilder,
  });

  final String label;
  final List<T> items;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onToggle;
  final String Function(T value) labelBuilder;
  final bool centered;
  final Color Function(T value)? colorBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasLabel = label.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (hasLabel)
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        if (hasLabel) const SizedBox(width: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chips = items
                  .map((item) {
                    final selected = isSelected(item);
                    final accent = colorBuilder?.call(item);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _CompactFilterChip(
                        label: labelBuilder(item),
                        selected: selected,
                        accent: accent,
                        onTap: () => onToggle(item),
                      ),
                    );
                  })
                  .toList(growable: false);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: centered
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: chips,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  const _CompactFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final baseColor = accent ?? Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? baseColor.withValues(alpha: accent == null ? 0.12 : 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? baseColor.withValues(alpha: accent == null ? 0.36 : 0.48)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected
                ? (accent ?? Theme.of(context).colorScheme.primary)
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _CreateOrderFab extends StatelessWidget {
  const _CreateOrderFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Agregar orden de servicio',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.16),
                colorScheme.primary,
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.note_add_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agregar',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Orden de servicio',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceOrderListCard extends StatelessWidget {
  const _ServiceOrderListCard({
    required this.order,
    required this.client,
    required this.clientName,
    required this.creatorName,
    required this.onTap,
    required this.statusBusy,
    required this.creatingNewOrder,
    required this.isTechnician,
    this.onCreateNewOrder,
    this.onChangeStatus,
    this.trailing,
  });

  final ServiceOrderModel order;
  final ClienteModel? client;
  final String clientName;
  final String creatorName;
  final VoidCallback onTap;
  final bool statusBusy;
  final bool creatingNewOrder;
  final bool isTechnician;
  final VoidCallback? onCreateNewOrder;
  final ValueChanged<ServiceOrderStatus>? onChangeStatus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locationUrl = client?.locationUrl;
    final locationPreview = parseClientLocationPreview(locationUrl);
    final locationUri = buildClientNavigationUri(locationPreview, locationUrl);
    final createdAt = order.createdAt.toLocal();
    final topLineText = DateFormat('dd/MM/yyyy · h:mm a', 'es_DO').format(createdAt);
    final isPriorityInstallation = order.serviceType == ServiceOrderType.instalacion;
    final creatorDisplayName = creatorName.trim();
    final hasCreatorName = creatorDisplayName.isNotEmpty;
    final clientDisplayName = clientName.trim();
    final hasClientName = clientDisplayName.isNotEmpty;
    final clientPhone = (client?.telefono ?? '').trim();
    final hasClientPhone = clientPhone.isNotEmpty;
    final hasClientInfo = hasClientName || hasClientPhone;
    final callUri = _buildPhoneUri(clientPhone);
    final whatsappUri = _buildWhatsAppUri(clientPhone);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF9FAFC), Color(0xFFF5F7FA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          topLineText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                      if (hasCreatorName) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            creatorDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                      if (isPriorityInstallation)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFD97706).withValues(alpha: 0.28),
                              ),
                            ),
                            child: const Text(
                              'Prioridad',
                              style: TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: !isTechnician && onChangeStatus != null ? 116 : 36,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Row(
                                    children: [
                                      _CompactInfoChip(
                                        icon: Icons.category_outlined,
                                        text: order.category.label,
                                      ),
                                      const SizedBox(width: 5),
                                      _CompactInfoChip(
                                        icon: Icons.build_circle_outlined,
                                        text: order.serviceType.label,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isTechnician) ...[
                                const SizedBox(width: 8),
                                if (locationUri != null)
                                  _TechnicianLocationButton(
                                    locationUri: locationUri,
                                    compact: true,
                                  ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                              ),
                            ),
                            child: Row(
                              children: [
                                if (hasClientInfo) ...[
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: RichText(
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        children: [
                                          if (hasClientName)
                                            TextSpan(
                                              text: clientDisplayName,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurface,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.1,
                                              ),
                                            ),
                                          if (hasClientPhone)
                                            TextSpan(
                                              text: hasClientName
                                                  ? '  ·  $clientPhone'
                                                  : clientPhone,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ] else
                                  const Spacer(),
                                _StatusBadge(status: order.status, compact: true),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (trailing != null && !isTechnician) ...[
                                SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: Center(child: trailing!),
                                ),
                                const SizedBox(width: 6),
                              ],
                            ],
                          ),
                          if (!isTechnician && onChangeStatus != null) ...[
                            const SizedBox(height: 8),
                            _InlineStatusButton(
                              order: order,
                              busy: statusBusy,
                              onSelected: onChangeStatus!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (onCreateNewOrder != null) ...[
                  const SizedBox(height: 9),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: creatingNewOrder ? null : onCreateNewOrder,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      icon: creatingNewOrder
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Nueva orden'),
                    ),
                  ),
                ],
                if (isTechnician) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (callUri != null) ...[
                        _ContactIconButton(
                          icon: Icons.call_outlined,
                          tooltip: 'Llamar cliente',
                          onTap: () => safeOpenUrl(context, callUri),
                          size: 42,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (whatsappUri != null) ...[
                        _ContactIconButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          tooltip: 'Escribir por WhatsApp',
                          onTap: () => safeOpenUrl(context, whatsappUri),
                          size: 42,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _TechnicianQuickActionButton(order: order),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelMetaPill extends StatelessWidget {
  const _PanelMetaPill({
    required this.icon,
    required this.text,
    this.accent,
  });

  final IconData icon;
  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: effectiveAccent.withValues(alpha: accent == null ? 0.06 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: effectiveAccent.withValues(alpha: accent == null ? 0.08 : 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: effectiveAccent),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: effectiveAccent,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactIconButton extends StatelessWidget {
  const _ContactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: onTap == null
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                : colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: onTap == null
                  ? colorScheme.outlineVariant.withValues(alpha: 0.35)
                  : colorScheme.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Icon(
            icon,
            size: size <= 30 ? 15 : 18,
            color: onTap == null
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
                : colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

Uri? _buildPhoneUri(String rawPhone) {
  final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }
  return Uri.parse('tel:$digits');
}

Uri? _buildWhatsAppUri(String rawPhone) {
  var digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }
  if (digits.length == 10) {
    digits = '1$digits';
  }
  return Uri.parse('https://wa.me/$digits');
}

class _InlineStatusButton extends StatelessWidget {
  const _InlineStatusButton({
    required this.order,
    required this.busy,
    required this.onSelected,
  });

  final ServiceOrderModel order;
  final bool busy;
  final ValueChanged<ServiceOrderStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    final statuses = [order.status, ...order.status.allowedNextStatuses]
        .fold<List<ServiceOrderStatus>>(<ServiceOrderStatus>[], (acc, item) {
          if (!acc.contains(item)) acc.add(item);
          return acc;
        });

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: busy
          ? null
          : () async {
              final selected = await showModalBottomSheet<ServiceOrderStatus>(
                context: context,
                showDragHandle: true,
                builder: (sheetContext) {
                  final theme = Theme.of(sheetContext);
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cambiar estado',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Selecciona el estado actual de la orden.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ...statuses.map(
                            (status) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _InlineStatusSheetOption(
                                status: status,
                                isCurrent: status == order.status,
                                onTap: () => Navigator.pop(sheetContext, status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

              if (selected == null || selected == order.status) {
                return;
              }
              onSelected(selected);
            },
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.55),
                ),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync_alt_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Estado',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _InlineStatusSheetOption extends StatelessWidget {
  const _InlineStatusSheetOption({
    required this.status,
    required this.isCurrent,
    required this.onTap,
  });

  final ServiceOrderStatus status;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? status.color.withValues(alpha: 0.45)
                : colorScheme.outlineVariant,
          ),
          color: isCurrent
              ? status.color.withValues(alpha: 0.1)
              : colorScheme.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: status.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isCurrent)
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: status.color,
              ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, this.compact = false});

  final ServiceOrderStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.22)),
        boxShadow: compact
            ? [
                BoxShadow(
                  color: status.color.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 12,
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

/// Botón de "Mini Prompt" (3 puntos) para técnicos.
/// Solo visible para usuarios con rol técnico.
class _TechnicianQuickActionButton extends ConsumerWidget {
  const _TechnicianQuickActionButton({required this.order});

  final ServiceOrderModel order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        backgroundColor: const Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: const Color(0xFF1D4ED8).withValues(alpha: 0.28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: const Text(
        'Gestión técnica',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () async {
        await showServiceOrderQuickActionsModal(
          context: context,
          ref: ref,
          orderId: order.id,
          order: order,
          onOrderUpdated: () {
            // Refresh the list when order is updated
            final controller = ref.read(serviceOrdersListControllerProvider.notifier);
            controller.refresh();
          },
        );
      },
    );
  }
}

class _TechnicianLocationButton extends StatelessWidget {
  const _TechnicianLocationButton({
    required this.locationUri,
    this.compact = false,
  });

  final Uri? locationUri;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final targetUri = locationUri;
    final theme = Theme.of(context);
    return FilledButton.icon(
      onPressed: targetUri == null ? null : () => safeOpenUrl(context, targetUri),
      style: FilledButton.styleFrom(
        minimumSize: Size(compact ? 0 : 120, compact ? 34 : 42),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 8 : 10,
        ),
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
        foregroundColor: theme.colorScheme.primary,
        elevation: 0,
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.16)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: Icon(Icons.near_me_rounded, size: compact ? 16 : 18),
      label: Text(
        'Ubicación',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: compact ? 12 : null,
        ),
      ),
    );
  }
}
