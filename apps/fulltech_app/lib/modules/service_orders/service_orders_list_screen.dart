import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/realtime/operations_realtime_service.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/custom_app_bar.dart';
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
  final TextEditingController _collapsedQuickSearchCtrl =
      TextEditingController();
  final Set<String> _busyOrderIds = <String>{};
  final Set<String> _creatingFromOrderIds = <String>{};
  bool _desktopControlsCollapsed = false;
  bool _mobileControlsCollapsed = true;
  bool _purgingAllDebug = false;
  StreamSubscription<OperationsRealtimeMessage>?
  _operationsRealtimeSubscription;

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
    _collapsedQuickSearchCtrl.dispose();
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

  Future<void> _purgeAllDebug() async {
    final confirmed = await confirmDebugAdminPurge(
      context,
      moduleLabel: 'operaciones',
      impactLabel: 'todas las órdenes de servicio visibles en este módulo',
    );
    if (!confirmed || !mounted) return;

    setState(() => _purgingAllDebug = true);
    try {
      final deleted = await ref
          .read(serviceOrdersListControllerProvider.notifier)
          .purgeAllDebug();
      if (!mounted) return;
      AppFeedback.showInfo(
        context,
        'Se limpiaron $deleted órdenes de servicio.',
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : '$e';
      AppFeedback.showError(context, message);
    } finally {
      if (mounted) {
        setState(() => _purgingAllDebug = false);
      }
    }
  }

  Future<void> _openFiltersSheet({
    required List<_FilterUserOption> availableCreators,
    required List<_FilterUserOption> availableTechnicians,
  }) async {
    final next = await showModalBottomSheet<ServiceOrdersFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _FiltersSheet(
          initialFilter: _filter,
          availableCreators: availableCreators,
          availableTechnicians: availableTechnicians,
        );
      },
    );
    if (next == null || !mounted) {
      return;
    }
    setState(() {
      _filter = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceOrdersListControllerProvider);
    final controller = ref.read(serviceOrdersListControllerProvider.notifier);
    final currentUser = ref.watch(authStateProvider).user;
    final canManageStatusAsRole =
        currentUser?.appRole.isAdmin == true ||
        currentUser?.appRole.isTechnician == true;
    final isAdmin = currentUser?.appRole.isAdmin ?? false;
    final currentUserId = currentUser?.id ?? '';
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopShellBreakpoint;
    final visibleOrders = _applyCollapsedQuickSearch(
      orders: _filter.apply(state.items),
      clientsById: state.clientsById,
      usersById: state.usersById,
    );
    final availableCreators = _buildFilterUserOptions(
      orders: state.items,
      usersById: state.usersById,
      userIdSelector: (order) => order.createdById,
    );
    final availableTechnicians = _buildFilterUserOptions(
      orders: state.items,
      usersById: state.usersById,
      userIdSelector: (order) => order.assignedToId,
    );
    final contentMaxWidth = isDesktop ? 1120.0 : double.infinity;
    final canShowPurgeAction = canUseDebugAdminAction(currentUser);
    final gpsReadyCount = visibleOrders.where((order) {
      final client = order.client ?? state.clientsById[order.clientId];
      final preview = parseClientLocationPreview(client?.locationUrl);
      return buildClientNavigationUri(preview, client?.locationUrl) != null;
    }).length;
    final scheduledCount = visibleOrders
        .where((order) => order.scheduledFor != null)
        .length;
    final pendingCount = visibleOrders
        .where((order) => order.status == ServiceOrderStatus.pendiente)
        .length;
    final inProgressCount = visibleOrders
        .where((order) => order.status == ServiceOrderStatus.enProceso)
        .length;

    return Scaffold(
      drawer: isDesktop
          ? null
          : buildAdaptiveDrawer(context, currentUser: currentUser),
      floatingActionButton: _CreateOrderFab(onPressed: _createOrder),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: CustomAppBar(
        title: 'Operaciones',
        toolbarHeight: 54,
        centerTitle: false,
        titleSpacing: isDesktop ? 16 : 0,
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          _PriorityMapButton(
            onPressed: () => context.push(Routes.clientesMapa),
          ),
          _ProfileAvatarButton(currentUser: currentUser),
          PopupMenuButton<_OperationsOverflowAction>(
            tooltip: 'Más opciones',
            enabled: !state.refreshing || canShowPurgeAction,
            onSelected: (action) async {
              switch (action) {
                case _OperationsOverflowAction.sync:
                  await controller.refresh();
                case _OperationsOverflowAction.purge:
                  await _purgeAllDebug();
              }
            },
            itemBuilder: (menuContext) {
              final colorScheme = Theme.of(menuContext).colorScheme;
              return [
                PopupMenuItem<_OperationsOverflowAction>(
                  value: _OperationsOverflowAction.sync,
                  enabled: !state.refreshing,
                  child: Row(
                    children: [
                      if (state.refreshing)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.1,
                            color: colorScheme.primary,
                          ),
                        )
                      else
                        const Icon(Icons.sync_rounded, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        state.refreshing ? 'Sincronizando...' : 'Sincronizar',
                      ),
                    ],
                  ),
                ),
                if (canShowPurgeAction)
                  PopupMenuItem<_OperationsOverflowAction>(
                    value: _OperationsOverflowAction.purge,
                    enabled: !_purgingAllDebug,
                    child: Row(
                      children: [
                        if (_purgingAllDebug)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.1,
                              color: colorScheme.error,
                            ),
                          )
                        else
                          Icon(
                            Icons.delete_sweep_rounded,
                            size: 18,
                            color: colorScheme.error,
                          ),
                        const SizedBox(width: 10),
                        Text(
                          _purgingAllDebug
                              ? 'Eliminando datos...'
                              : 'Eliminar todo',
                        ),
                      ],
                    ),
                  ),
              ];
            },
            icon: const Icon(Icons.more_vert_rounded),
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
        child: state.error != null && state.items.isEmpty && !state.refreshing
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
                          Text(state.error!, textAlign: TextAlign.center),
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
                          child: isDesktop
                              ? Column(
                                  children: [
                                    _DesktopOperationsOverviewPanel(
                                      filter: _filter,
                                      activeCount: visibleOrders.length,
                                      pendingCount: pendingCount,
                                      inProgressCount: inProgressCount,
                                      gpsReadyCount: gpsReadyCount,
                                      scheduledCount: scheduledCount,
                                      refreshing: state.refreshing,
                                    ),
                                    const SizedBox(height: 12),
                                    if (!_desktopControlsCollapsed)
                                      _OperationsControlPanel(
                                        filter: _filter,
                                        activeCount: visibleOrders.length,
                                        refreshing: state.refreshing,
                                        searchController:
                                            _collapsedQuickSearchCtrl,
                                        onSearchChanged: (_) {
                                          setState(() {});
                                        },
                                        onClearSearch: () {
                                          _collapsedQuickSearchCtrl.clear();
                                          setState(() {});
                                        },
                                        onOpenFilters: () {
                                          _openFiltersSheet(
                                            availableCreators:
                                                availableCreators,
                                            availableTechnicians:
                                                availableTechnicians,
                                          );
                                        },
                                        onCollapse: () {
                                          setState(() {
                                            _desktopControlsCollapsed = true;
                                          });
                                        },
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
                                            final nextStatuses = {
                                              ..._filter.statuses,
                                            };
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
                                            final nextTypes = {
                                              ..._filter.serviceTypes,
                                            };
                                            if (nextTypes.contains(
                                              serviceType,
                                            )) {
                                              nextTypes.remove(serviceType);
                                            } else {
                                              nextTypes.add(serviceType);
                                            }
                                            _filter = _filter.copyWith(
                                              serviceTypes: nextTypes,
                                            );
                                          });
                                        },
                                      )
                                    else
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: _CollapsedOperationsPanelToggle(
                                          activeCount: visibleOrders.length,
                                          hasActiveFilters:
                                              _filter.hasActiveFilters,
                                          searchController:
                                              _collapsedQuickSearchCtrl,
                                          onSearchChanged: (_) {
                                            setState(() {});
                                          },
                                          onClearSearch: () {
                                            _collapsedQuickSearchCtrl.clear();
                                            setState(() {});
                                          },
                                          onOpenFilters: () {
                                            _openFiltersSheet(
                                              availableCreators:
                                                  availableCreators,
                                              availableTechnicians:
                                                  availableTechnicians,
                                            );
                                          },
                                          onTap: () {
                                            setState(() {
                                              _desktopControlsCollapsed = false;
                                            });
                                          },
                                        ),
                                      ),
                                  ],
                                )
                              : !_mobileControlsCollapsed
                              ? _OperationsControlPanel(
                                  filter: _filter,
                                  activeCount: visibleOrders.length,
                                  refreshing: state.refreshing,
                                  searchController: _collapsedQuickSearchCtrl,
                                  onSearchChanged: (_) {
                                    setState(() {});
                                  },
                                  onClearSearch: () {
                                    _collapsedQuickSearchCtrl.clear();
                                    setState(() {});
                                  },
                                  onOpenFilters: () {
                                    _openFiltersSheet(
                                      availableCreators: availableCreators,
                                      availableTechnicians:
                                          availableTechnicians,
                                    );
                                  },
                                  onCollapse: () {
                                    setState(() {
                                      _mobileControlsCollapsed = true;
                                    });
                                  },
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
                                      final nextStatuses = {
                                        ..._filter.statuses,
                                      };
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
                                      final nextTypes = {
                                        ..._filter.serviceTypes,
                                      };
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
                                )
                              : Align(
                                  alignment: Alignment.centerRight,
                                  child: _CollapsedOperationsPanelToggle(
                                    activeCount: visibleOrders.length,
                                    hasActiveFilters: _filter.hasActiveFilters,
                                    searchController: _collapsedQuickSearchCtrl,
                                    onSearchChanged: (_) {
                                      setState(() {});
                                    },
                                    onClearSearch: () {
                                      _collapsedQuickSearchCtrl.clear();
                                      setState(() {});
                                    },
                                    onOpenFilters: () {
                                      _openFiltersSheet(
                                        availableCreators: availableCreators,
                                        availableTechnicians:
                                            availableTechnicians,
                                      );
                                    },
                                    onTap: () {
                                      setState(() {
                                        _mobileControlsCollapsed = false;
                                      });
                                    },
                                  ),
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
                  final canChangeOrderStatus =
                      canManageStatusAsRole ||
                      currentUserId == order.createdById;
                  final client =
                      order.client ?? state.clientsById[order.clientId];
                  final assignedToId = (order.assignedToId ?? '').trim();
                  final technicianName = assignedToId.isEmpty
                      ? ''
                      : (state.usersById[assignedToId]?.nombreCompleto ??
                            assignedToId);
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
                              state
                                  .usersById[order.createdById]
                                  ?.nombreCompleto ??
                              order.createdById,
                          technicianName: technicianName,
                          statusBusy: _busyOrderIds.contains(order.id),
                          isTechnician:
                              currentUser?.appRole.isTechnician ?? false,
                          canPromoteStatus: canManageStatusAsRole,
                          onChangeStatus: canChangeOrderStatus
                              ? (status) => _changeOrderStatus(order, status)
                              : null,
                          creatingNewOrder: _creatingFromOrderIds.contains(
                            order.id,
                          ),
                          onCreateNewOrder: order.isCloneSourceAllowed
                              ? () => _createOrderFromSource(order)
                              : null,
                          onEdit:
                              (isAdmin || currentUserId == order.createdById)
                              ? () => _editOrder(order)
                              : null,
                          onDelete: isAdmin ? () => _deleteOrder(order) : null,
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
      ref
          .read(serviceOrdersListControllerProvider.notifier)
          .upsertOrder(updated);
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Estado actualizado');
    } catch (error) {
      ref
          .read(serviceOrdersListControllerProvider.notifier)
          .upsertOrder(previousOrder);
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error is ApiException
            ? error.message
            : 'No se pudo actualizar el estado',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOrderIds.remove(order.id);
        });
      }
    }
  }

  List<ServiceOrderModel> _applyCollapsedQuickSearch({
    required List<ServiceOrderModel> orders,
    required Map<String, ClienteModel> clientsById,
    required Map<String, UserModel> usersById,
  }) {
    final query = _normalizeCollapsedQuickSearch(
      _collapsedQuickSearchCtrl.text,
    );
    if (query.isEmpty) {
      return orders;
    }

    return orders
        .where((order) {
          final client = order.client ?? clientsById[order.clientId];
          final creatorName =
              usersById[order.createdById]?.nombreCompleto ?? '';
          final technicianName = order.assignedToId == null
              ? ''
              : (usersById[order.assignedToId!]?.nombreCompleto ?? '');
          final searchable = _normalizeCollapsedQuickSearch(
            [
              order.id,
              order.clientId,
              order.quotationId ?? '',
              order.category.label,
              order.serviceType.label,
              order.status.label,
              client?.nombre ?? '',
              client?.telefono ?? '',
              creatorName,
              technicianName,
              order.technicalNote ?? '',
              order.extraRequirements ?? '',
            ].join(' '),
          );
          return searchable.contains(query);
        })
        .toList(growable: false);
  }

  String _normalizeCollapsedQuickSearch(String value) {
    return value.toLowerCase().trim();
  }
}

enum ServiceOrdersDatePreset { all, today, thisWeek, custom }

enum ServiceOrdersCompletionFilter { any, finalizadas, noFinalizadas }

extension ServiceOrdersCompletionFilterX on ServiceOrdersCompletionFilter {
  String get label {
    switch (this) {
      case ServiceOrdersCompletionFilter.any:
        return 'Todas';
      case ServiceOrdersCompletionFilter.finalizadas:
        return 'Finalizadas';
      case ServiceOrdersCompletionFilter.noFinalizadas:
        return 'No finalizadas';
    }
  }

  IconData get icon {
    switch (this) {
      case ServiceOrdersCompletionFilter.any:
        return Icons.tune_rounded;
      case ServiceOrdersCompletionFilter.finalizadas:
        return Icons.verified_rounded;
      case ServiceOrdersCompletionFilter.noFinalizadas:
        return Icons.pending_actions_rounded;
    }
  }
}

class ServiceOrdersFilter {
  const ServiceOrdersFilter({
    required this.datePreset,
    this.completionFilter = ServiceOrdersCompletionFilter.any,
    this.statuses = const <ServiceOrderStatus>{},
    this.serviceTypes = const <ServiceOrderType>{},
    this.creatorIds = const <String>{},
    this.technicianIds = const <String>{},
    this.customRange,
  });

  const ServiceOrdersFilter.today()
    : datePreset = ServiceOrdersDatePreset.today,
      completionFilter = ServiceOrdersCompletionFilter.any,
      statuses = const <ServiceOrderStatus>{},
      serviceTypes = const <ServiceOrderType>{},
      creatorIds = const <String>{},
      technicianIds = const <String>{},
      customRange = null;

  const ServiceOrdersFilter.mainDefault()
    : datePreset = ServiceOrdersDatePreset.all,
      completionFilter = ServiceOrdersCompletionFilter.any,
      statuses = const <ServiceOrderStatus>{
        ServiceOrderStatus.pendiente,
        ServiceOrderStatus.enProceso,
      },
      serviceTypes = const <ServiceOrderType>{},
      creatorIds = const <String>{},
      technicianIds = const <String>{},
      customRange = null;

  final ServiceOrdersDatePreset datePreset;
  final ServiceOrdersCompletionFilter completionFilter;
  final Set<ServiceOrderStatus> statuses;
  final Set<ServiceOrderType> serviceTypes;
  final Set<String> creatorIds;
  final Set<String> technicianIds;
  final DateTimeRange? customRange;

  bool get isMainDefault {
    return datePreset == ServiceOrdersDatePreset.all &&
        completionFilter == ServiceOrdersCompletionFilter.any &&
        serviceTypes.isEmpty &&
        creatorIds.isEmpty &&
        technicianIds.isEmpty &&
        statuses.length == 2 &&
        statuses.contains(ServiceOrderStatus.pendiente) &&
        statuses.contains(ServiceOrderStatus.enProceso);
  }

  ServiceOrdersFilter copyWith({
    ServiceOrdersDatePreset? datePreset,
    ServiceOrdersCompletionFilter? completionFilter,
    Set<ServiceOrderStatus>? statuses,
    Set<ServiceOrderType>? serviceTypes,
    Set<String>? creatorIds,
    Set<String>? technicianIds,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
  }) {
    return ServiceOrdersFilter(
      datePreset: datePreset ?? this.datePreset,
      completionFilter: completionFilter ?? this.completionFilter,
      statuses: statuses ?? this.statuses,
      serviceTypes: serviceTypes ?? this.serviceTypes,
      creatorIds: creatorIds ?? this.creatorIds,
      technicianIds: technicianIds ?? this.technicianIds,
      customRange: clearCustomRange ? null : (customRange ?? this.customRange),
    );
  }

  bool get hasActiveFilters {
    return !isMainDefault;
  }

  int get selectionCount {
    var total = 0;
    if (datePreset != ServiceOrdersDatePreset.all) {
      total += 1;
    }
    if (completionFilter != ServiceOrdersCompletionFilter.any) {
      total += 1;
    }
    total += statuses.length;
    total += serviceTypes.length;
    total += creatorIds.length;
    total += technicianIds.length;
    return total;
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
    if (completionFilter != ServiceOrdersCompletionFilter.any) {
      chips.add(completionFilter.label);
    }
    chips.addAll(statuses.map((status) => status.label));
    chips.addAll(serviceTypes.map((serviceType) => serviceType.label));
    if (creatorIds.isNotEmpty) {
      chips.add(
        creatorIds.length == 1 ? '1 creador' : '${creatorIds.length} creadores',
      );
    }
    if (technicianIds.isNotEmpty) {
      chips.add(
        technicianIds.length == 1
            ? '1 técnico'
            : '${technicianIds.length} técnicos',
      );
    }
    return chips;
  }

  List<String> get insightChips {
    final chips = <String>[];
    if (completionFilter != ServiceOrdersCompletionFilter.any) {
      chips.add(completionFilter.label);
    }
    if (creatorIds.isNotEmpty) {
      chips.add(
        creatorIds.length == 1 ? '1 creador' : '${creatorIds.length} creadores',
      );
    }
    if (technicianIds.isNotEmpty) {
      chips.add(
        technicianIds.length == 1
            ? '1 técnico'
            : '${technicianIds.length} técnicos',
      );
    }
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
          final matchesCompletion = switch (completionFilter) {
            ServiceOrdersCompletionFilter.any => true,
            ServiceOrdersCompletionFilter.finalizadas =>
              order.status == ServiceOrderStatus.finalizado,
            ServiceOrdersCompletionFilter.noFinalizadas =>
              order.status != ServiceOrderStatus.finalizado,
          };
          if (!matchesCompletion) {
            return false;
          }
          if (statuses.isNotEmpty && !statuses.contains(order.status)) {
            return false;
          }
          if (serviceTypes.isNotEmpty &&
              !serviceTypes.contains(order.serviceType)) {
            return false;
          }
          if (creatorIds.isNotEmpty &&
              !creatorIds.contains(order.createdById)) {
            return false;
          }
          final assignedToId = order.assignedToId?.trim();
          if (technicianIds.isNotEmpty &&
              (assignedToId == null || !technicianIds.contains(assignedToId))) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }
}

class _FilterUserOption {
  const _FilterUserOption({
    required this.id,
    required this.label,
    required this.role,
  });

  final String id;
  final String label;
  final AppRole role;

  String get roleLabel {
    switch (role) {
      case AppRole.admin:
        return 'Administrador';
      case AppRole.asistente:
        return 'Asistente';
      case AppRole.vendedor:
        return 'Vendedor';
      case AppRole.marketing:
        return 'Marketing';
      case AppRole.tecnico:
        return 'Técnico';
      case AppRole.unknown:
        return 'Usuario';
    }
  }

  String get initials {
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'FT';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

List<_FilterUserOption> _buildFilterUserOptions({
  required List<ServiceOrderModel> orders,
  required Map<String, UserModel> usersById,
  required String? Function(ServiceOrderModel order) userIdSelector,
}) {
  final ids = <String>{};
  for (final order in orders) {
    final userId = userIdSelector(order)?.trim() ?? '';
    if (userId.isNotEmpty) {
      ids.add(userId);
    }
  }

  final options = ids
      .map((id) {
        final user = usersById[id];
        final fallbackLabel = id.length <= 8
            ? 'Usuario $id'
            : 'Usuario ${id.substring(0, 8)}';
        return _FilterUserOption(
          id: id,
          label: (user?.nombreCompleto ?? '').trim().isEmpty
              ? fallbackLabel
              : user!.nombreCompleto.trim(),
          role: user?.appRole ?? AppRole.unknown,
        );
      })
      .toList(growable: false);

  options.sort(
    (left, right) =>
        left.label.toLowerCase().compareTo(right.label.toLowerCase()),
  );
  return options;
}

enum _OperationsOverflowAction { sync, purge }

class _PriorityMapButton extends StatelessWidget {
  const _PriorityMapButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Mapa de clientes',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.map_rounded, size: 21),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatarButton extends StatefulWidget {
  const _ProfileAvatarButton({required this.currentUser});

  final UserModel? currentUser;

  @override
  State<_ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<_ProfileAvatarButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.currentUser?.fotoPersonalUrl;
    final name = widget.currentUser?.nombreCompleto ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = Curves.easeInOut.transform(_controller.value);
          return Transform.scale(
            scale: 1 + (pulse * 0.035),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(
                      alpha: 0.10 + (pulse * 0.08),
                    ),
                    blurRadius: 16 + (pulse * 6),
                    spreadRadius: pulse * 1.2,
                  ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: Tooltip(
          message: 'Mi perfil',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => context.push(Routes.profile),
              child: Ink(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: UserAvatar(
                  radius: 19,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  imageUrl: photoUrl,
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({
    required this.initialFilter,
    required this.availableCreators,
    required this.availableTechnicians,
  });

  final ServiceOrdersFilter initialFilter;
  final List<_FilterUserOption> availableCreators;
  final List<_FilterUserOption> availableTechnicians;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late Set<ServiceOrderStatus> _statuses;
  late Set<ServiceOrderType> _serviceTypes;
  late ServiceOrdersDatePreset _datePreset;
  late ServiceOrdersCompletionFilter _completionFilter;
  late Set<String> _creatorIds;
  late Set<String> _technicianIds;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _statuses = {...widget.initialFilter.statuses};
    _serviceTypes = {...widget.initialFilter.serviceTypes};
    _completionFilter = widget.initialFilter.completionFilter;
    _creatorIds = {...widget.initialFilter.creatorIds};
    _technicianIds = {...widget.initialFilter.technicianIds};
    _datePreset = widget.initialFilter.datePreset;
    _customRange = widget.initialFilter.customRange;
  }

  int get _selectedCount {
    return ServiceOrdersFilter(
      datePreset: _datePreset,
      completionFilter: _completionFilter,
      statuses: _statuses,
      serviceTypes: _serviceTypes,
      creatorIds: _creatorIds,
      technicianIds: _technicianIds,
      customRange: _customRange,
    ).selectionCount;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.surface, colorScheme.surfaceContainerLowest],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompactHeader(
                selectedCount: _selectedCount,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              _CompactSection(
                title: 'Cierre',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrdersCompletionFilter.values
                      .map(
                        (value) => _ChoiceFilterTile(
                          label: value.label,
                          icon: value.icon,
                          selected: _completionFilter == value,
                          compact: true,
                          onTap: () {
                            setState(() {
                              _completionFilter = value;
                            });
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 10),
              _CompactSection(
                title: 'Estado',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrderStatus.values
                      .map((status) {
                        final selected = _statuses.contains(status);
                        return FilterChip(
                          selected: selected,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
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
              const SizedBox(height: 10),
              _CompactSection(
                title: 'Servicio',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrderType.values
                      .map((serviceType) {
                        final selected = _serviceTypes.contains(serviceType);
                        return FilterChip(
                          selected: selected,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
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
              const SizedBox(height: 10),
              _CompactSection(
                title: 'Fecha',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ChoiceFilterTile(
                      label: 'Todas',
                      icon: Icons.all_inbox_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.all,
                      compact: true,
                      onTap: () {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.all;
                        });
                      },
                    ),
                    _ChoiceFilterTile(
                      label: 'Hoy',
                      icon: Icons.today_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.today,
                      compact: true,
                      onTap: () {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.today;
                        });
                      },
                    ),
                    _ChoiceFilterTile(
                      label: 'Semana',
                      icon: Icons.date_range_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.thisWeek,
                      compact: true,
                      onTap: () {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.thisWeek;
                        });
                      },
                    ),
                    _ChoiceFilterTile(
                      label: 'Rango',
                      icon: Icons.edit_calendar_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.custom,
                      compact: true,
                      onTap: () async {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.custom;
                        });
                        await _pickCustomRange();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SummarySelectorTile(
                      label: 'Creador',
                      summary: _selectionSummary(
                        selectedIds: _creatorIds,
                        options: widget.availableCreators,
                      ),
                      icon: Icons.person_search_rounded,
                      accent: colorScheme.primary,
                      onTap: () async {
                        final next = await _pickUserOptions(
                          title: 'Filtrar por creador',
                          options: widget.availableCreators,
                          selectedIds: _creatorIds,
                          accent: colorScheme.primary,
                        );
                        if (next == null || !mounted) {
                          return;
                        }
                        setState(() {
                          _creatorIds = next;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummarySelectorTile(
                      label: 'Técnico',
                      summary: _selectionSummary(
                        selectedIds: _technicianIds,
                        options: widget.availableTechnicians,
                      ),
                      icon: Icons.engineering_rounded,
                      accent: const Color(0xFF0F766E),
                      onTap: () async {
                        final next = await _pickUserOptions(
                          title: 'Filtrar por técnico',
                          options: widget.availableTechnicians,
                          selectedIds: _technicianIds,
                          accent: const Color(0xFF0F766E),
                        );
                        if (next == null || !mounted) {
                          return;
                        }
                        setState(() {
                          _technicianIds = next;
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_datePreset == ServiceOrdersDatePreset.custom) ...[
                const SizedBox(height: 10),
                _CustomDateRangeBanner(
                  range: _customRange,
                  compact: true,
                  onTap: _pickCustomRange,
                ),
              ],
              const SizedBox(height: 14),
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
                  const SizedBox(width: 10),
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
                            completionFilter: _completionFilter,
                            statuses: _statuses,
                            serviceTypes: _serviceTypes,
                            creatorIds: _creatorIds,
                            technicianIds: _technicianIds,
                            customRange:
                                effectivePreset ==
                                    ServiceOrdersDatePreset.custom
                                ? _customRange
                                : null,
                          ),
                        );
                      },
                      child: const Text('Aplicar'),
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

  String _selectionSummary({
    required Set<String> selectedIds,
    required List<_FilterUserOption> options,
  }) {
    if (selectedIds.isEmpty) {
      return 'Todos';
    }
    if (selectedIds.length == 1) {
      for (final option in options) {
        if (selectedIds.contains(option.id)) {
          return option.label;
        }
      }
    }
    return '${selectedIds.length} seleccionados';
  }

  Future<Set<String>?> _pickUserOptions({
    required String title,
    required List<_FilterUserOption> options,
    required Set<String> selectedIds,
    required Color accent,
  }) async {
    return showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _UserSelectionSheet(
        title: title,
        options: options,
        selectedIds: selectedIds,
        accent: accent,
      ),
    );
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.selectedCount, required this.onClose});

  final int selectedCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.12),
            colorScheme.tertiary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filtros',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  selectedCount == 0 ? 'Base' : '$selectedCount activos',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactSection extends StatelessWidget {
  const _CompactSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ChoiceFilterTile extends StatelessWidget {
  const _ChoiceFilterTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 9 : 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.36)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? 16 : 18,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: compact ? 6 : 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: compact ? 13 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySelectorTile extends StatelessWidget {
  const _SummarySelectorTile({
    required this.label,
    required this.summary,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String summary;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSelectionSheet extends StatefulWidget {
  const _UserSelectionSheet({
    required this.title,
    required this.options,
    required this.selectedIds,
    required this.accent,
  });

  final String title;
  final List<_FilterUserOption> options;
  final Set<String> selectedIds;
  final Color accent;

  @override
  State<_UserSelectionSheet> createState() => _UserSelectionSheetState();
}

class _UserSelectionSheetState extends State<_UserSelectionSheet> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.selectedIds};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedIds.clear();
                    });
                  },
                  child: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.options
                      .map(
                        (option) => _IdentityFilterChip(
                          option: option,
                          selected: _selectedIds.contains(option.id),
                          accent: widget.accent,
                          compact: true,
                          onTap: () {
                            setState(() {
                              if (_selectedIds.contains(option.id)) {
                                _selectedIds.remove(option.id);
                              } else {
                                _selectedIds.add(option.id);
                              }
                            });
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selectedIds),
                    child: Text(
                      _selectedIds.isEmpty ? 'Aplicar todos' : 'Aplicar',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityFilterChip extends StatelessWidget {
  const _IdentityFilterChip({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final _FilterUserOption option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: compact ? 180 : 220,
        padding: EdgeInsets.all(compact ? 10 : 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.4)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: compact ? 16 : 18,
              backgroundColor: accent.withValues(alpha: selected ? 0.22 : 0.12),
              child: Text(
                option.initials,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 12 : null,
                ),
              ),
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? accent : colorScheme.onSurface,
                      fontSize: compact ? 13 : null,
                    ),
                  ),
                  SizedBox(height: compact ? 1 : 2),
                  Text(
                    option.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: compact ? 11 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

class _CustomDateRangeBanner extends StatelessWidget {
  const _CustomDateRangeBanner({
    required this.range,
    required this.onTap,
    this.compact = false,
  });

  final DateTimeRange? range;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = range == null
        ? 'Selecciona un rango'
        : '${DateFormat('dd/MM/yyyy').format(range!.start)} - ${DateFormat('dd/MM/yyyy').format(range!.end)}';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : null,
                ),
              ),
            ),
            TextButton(onPressed: onTap, child: const Text('Cambiar')),
          ],
        ),
      ),
    );
  }
}

class _OperationsControlPanel extends StatelessWidget {
  const _OperationsControlPanel({
    required this.filter,
    required this.activeCount,
    required this.refreshing,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onOpenFilters,
    required this.onCollapse,
    required this.onToggleStatus,
    required this.onToggleServiceType,
    required this.onReset,
  });

  final ServiceOrdersFilter filter;
  final int activeCount;
  final bool refreshing;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback? onCollapse;
  final ValueChanged<ServiceOrderStatus> onToggleStatus;
  final ValueChanged<ServiceOrderType> onToggleServiceType;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE d MMM', 'es_DO').format(now);
    final timeLabel = DateFormat('h:mm a', 'es_DO').format(now);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.surface, colorScheme.surfaceContainerLowest],
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
                        if (refreshing) ...[
                          const SizedBox(width: 6),
                          _PanelMetaPill(
                            icon: Icons.sync_rounded,
                            text: 'Sincronizando',
                            accent: colorScheme.primary,
                          ),
                        ],
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
                if (onCollapse != null)
                  IconButton(
                    tooltip: 'Ocultar panel',
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    onPressed: onCollapse,
                    icon: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _OperationsQuickSearchField(
              controller: searchController,
              onChanged: onSearchChanged,
              onClear: onClearSearch,
              onOpenFilters: onOpenFilters,
              hasActiveFilters: filter.hasActiveFilters,
              hintText: 'Buscar por cliente, orden o técnico',
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
            if (filter.insightChips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filter.insightChips
                    .map((chip) => _FilterInsightBadge(label: chip))
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollapsedOperationsPanelToggle extends StatelessWidget {
  const _CollapsedOperationsPanelToggle({
    required this.activeCount,
    required this.hasActiveFilters,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onOpenFilters,
    required this.onTap,
  });

  final int activeCount;
  final bool hasActiveFilters;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final preferredSearchWidth = screenWidth >= 900
        ? 340.0
        : screenWidth >= 600
        ? 280.0
        : 220.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: preferredSearchWidth),
                  child: _OperationsQuickSearchField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    onClear: onClearSearch,
                    onOpenFilters: onOpenFilters,
                    hasActiveFilters: hasActiveFilters,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.78),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.025),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.dashboard_customize_outlined,
                        size: 15,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Panel',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: hasActiveFilters
                              ? colorScheme.primary.withValues(alpha: 0.10)
                              : colorScheme.surfaceContainerHighest.withValues(
                                  alpha: 0.45,
                                ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasActiveFilters
                                  ? Icons.filter_alt_outlined
                                  : Icons.layers_outlined,
                              size: 11,
                              color: hasActiveFilters
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasActiveFilters ? 'Filtros' : '$activeCount',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: hasActiveFilters
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OperationsQuickSearchField extends StatelessWidget {
  const _OperationsQuickSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onOpenFilters,
    required this.hasActiveFilters,
    this.hintText = 'Buscar',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;
  final bool hasActiveFilters;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasSearchText = controller.text.trim().isNotEmpty;
    final inputTextStyle = theme.textTheme.labelMedium?.copyWith(
      fontSize: 11.8,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.05,
      height: 1,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasActiveFilters
                ? colorScheme.primary.withValues(alpha: 0.44)
                : colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.014),
              blurRadius: 5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 15,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  style: inputTextStyle,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hintText,
                    hintStyle: inputTextStyle?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasSearchText)
                    _SearchFieldIconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: onClear,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (hasSearchText) const SizedBox(width: 2),
                  Container(
                    width: 1,
                    height: 12,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.38),
                  ),
                  const SizedBox(width: 4),
                  _SearchFieldIconButton(
                    tooltip: 'Filtros',
                    onPressed: onOpenFilters,
                    size: 30,
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.filter_alt_outlined,
                          size: 17,
                          color: hasActiveFilters
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        if (hasActiveFilters)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.surface,
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
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
}

class _SearchFieldIconButton extends StatelessWidget {
  const _SearchFieldIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.size = 22,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        splashRadius: 13,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: icon,
      ),
    );

    if (onPressed == null) {
      return IgnorePointer(child: button);
    }
    return button;
  }
}

class _FilterInsightBadge extends StatelessWidget {
  const _FilterInsightBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          height: 1,
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
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
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

class _DesktopOperationsOverviewPanel extends StatelessWidget {
  const _DesktopOperationsOverviewPanel({
    required this.filter,
    required this.activeCount,
    required this.pendingCount,
    required this.inProgressCount,
    required this.gpsReadyCount,
    required this.scheduledCount,
    required this.refreshing,
  });

  final ServiceOrdersFilter filter;
  final int activeCount;
  final int pendingCount;
  final int inProgressCount;
  final int gpsReadyCount;
  final int scheduledCount;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final dateLabel = DateFormat('EEE d MMM · h:mm a', 'es_DO').format(now);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PanelMetaPill(icon: Icons.dashboard_outlined, text: 'Resumen'),
            _PanelMetaPill(
              icon: Icons.tune_rounded,
              text: filter.summaryLabel,
              accent: colorScheme.primary,
            ),
            _PanelMetaPill(
              icon: Icons.calendar_month_rounded,
              text: _capitalize(dateLabel),
            ),
            _PanelMetaPill(
              icon: Icons.layers_outlined,
              text: '$activeCount activas',
            ),
            _PanelMetaPill(
              icon: Icons.pending_actions_rounded,
              text: '$pendingCount pendientes',
              accent: const Color(0xFFD97706),
            ),
            _PanelMetaPill(
              icon: Icons.construction_rounded,
              text: '$inProgressCount en proceso',
              accent: const Color(0xFF0F6CBD),
            ),
            _PanelMetaPill(
              icon: Icons.location_on_outlined,
              text: '$gpsReadyCount con GPS',
              accent: const Color(0xFF047857),
            ),
            _PanelMetaPill(
              icon: Icons.event_available_rounded,
              text: '$scheduledCount agendadas',
              accent: const Color(0xFF7C3AED),
            ),
            if (refreshing)
              _PanelMetaPill(
                icon: Icons.sync_rounded,
                text: 'Sincronizando',
                accent: colorScheme.primary,
              ),
          ],
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
    required this.technicianName,
    required this.onTap,
    required this.statusBusy,
    required this.creatingNewOrder,
    required this.isTechnician,
    required this.canPromoteStatus,
    this.onCreateNewOrder,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
  });

  final ServiceOrderModel order;
  final ClienteModel? client;
  final String clientName;
  final String creatorName;
  final String technicianName;
  final VoidCallback onTap;
  final bool statusBusy;
  final bool creatingNewOrder;
  final bool isTechnician;
  final bool canPromoteStatus;
  final VoidCallback? onCreateNewOrder;
  final ValueChanged<ServiceOrderStatus>? onChangeStatus;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;
    final locationUrl = client?.locationUrl;
    final locationPreview = parseClientLocationPreview(locationUrl);
    final locationUri = buildClientNavigationUri(locationPreview, locationUrl);
    final createdAt = order.createdAt.toLocal();
    final topLineText = DateFormat(
      'dd/MM/yyyy · h:mm a',
      'es_DO',
    ).format(createdAt);
    final priorityStyle = _resolveServiceTypePriorityStyle(order.serviceType);
    final creatorDisplayName = creatorName.trim();
    final creatorFirstName = _extractFirstName(creatorDisplayName);
    final creatorCompactLabel = _compactCreatorLabel(creatorDisplayName);
    final hasCreatorName = creatorDisplayName.isNotEmpty;
    final clientDisplayName = clientName.trim();
    final clientPhone = (client?.telefono ?? '').trim();
    final hasClientPhone = clientPhone.isNotEmpty;
    final serviceCityLabel = _extractServiceCity(
      address: client?.direccion,
      locationUrl: client?.locationUrl,
    );
    final callUri = _buildPhoneUri(clientPhone);
    final whatsappUri = _buildWhatsAppUri(clientPhone);

    if (isDesktop) {
      final assignedLabel = technicianName.trim().isEmpty
          ? 'Sin técnico asignado'
          : technicianName.trim();
      final scheduleLabel = order.scheduledFor == null
          ? 'Sin agenda definida'
          : DateFormat(
              'dd/MM/yyyy · h:mm a',
              'es_DO',
            ).format(order.scheduledFor!.toLocal());
      final detailSummary = _firstMeaningfulText(
        order.extraRequirements,
        order.technicalNote,
      );
      final gpsLabel =
          locationPreview.latitude != null && locationPreview.longitude != null
          ? '${locationPreview.latitude!.toStringAsFixed(5)}, ${locationPreview.longitude!.toStringAsFixed(5)}'
          : (locationUri != null ? 'Ubicación vinculada' : 'Sin GPS');

      final filesLabel =
          '${order.referenceItems.length} ref. · ${order.technicalEvidenceItems.length} evid.';
      final creatorLabel = hasCreatorName
          ? 'Creó $creatorFirstName'
          : 'Sin creador visible';

      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.alphaBlend(
                    priorityStyle.backgroundTint.withValues(alpha: 0.45),
                    const Color(0xFFFAFBFD),
                  ),
                  Color.alphaBlend(
                    priorityStyle.backgroundTint.withValues(alpha: 0.18),
                    const Color(0xFFF4F7FB),
                  ),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: priorityStyle.borderColor.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    margin: const EdgeInsets.only(top: 1, right: 10),
                    decoration: BoxDecoration(
                      color: priorityStyle.edgeColor.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _PanelMetaPill(
                                    icon: Icons.tag_rounded,
                                    text: '#${_compactOrderId(order.id)}',
                                    accent: theme.colorScheme.primary,
                                  ),
                                  _PanelMetaPill(
                                    icon: Icons.calendar_today_outlined,
                                    text: topLineText,
                                  ),
                                  if (hasCreatorName)
                                    _PanelMetaPill(
                                      icon: Icons.person_outline_rounded,
                                      text: 'Vendedor: $creatorFirstName',
                                      accent: theme.colorScheme.tertiary,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(status: order.status, compact: true),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          clientDisplayName.isEmpty
                              ? 'Cliente sin nombre'
                              : clientDisplayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (detailSummary != null) ...[
                          Text(
                            detailSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _DesktopInfoBlock(
                                icon: Icons.build_circle_outlined,
                                label: 'Servicio',
                                primary:
                                    '${order.category.label} · ${order.serviceType.label}',
                                secondary: scheduleLabel,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DesktopInfoBlock(
                                icon: Icons.location_on_outlined,
                                label: 'Ubicación',
                                primary: gpsLabel,
                                secondary: filesLabel,
                                accent: locationUri != null
                                    ? const Color(0xFF047857)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DesktopInfoBlock(
                                icon: Icons.engineering_outlined,
                                label: 'Responsables',
                                primary: assignedLabel,
                                secondary: creatorLabel,
                              ),
                            ),
                          ],
                        ),
                        if (hasClientPhone) ...[
                          const SizedBox(height: 6),
                          _DesktopInlineInfoChip(
                            icon: Icons.phone_outlined,
                            text: clientPhone,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 124,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (onChangeStatus != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _InlineStatusButton(
                              order: order,
                              busy: statusBusy,
                              canPromoteStatus: canPromoteStatus,
                              onSelected: onChangeStatus!,
                            ),
                          ),
                        if (onEdit != null && !isTechnician) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _OrderActionsMenu(
                              busy: statusBusy,
                              onEdit: onEdit!,
                              onDelete: onDelete,
                            ),
                          ),
                        ],
                        if (onCreateNewOrder != null) ...[
                          const SizedBox(height: 6),
                          FilledButton.tonalIcon(
                            onPressed: creatingNewOrder
                                ? null
                                : onCreateNewOrder,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 7,
                              ),
                              minimumSize: const Size.fromHeight(32),
                            ),
                            icon: creatingNewOrder
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Nueva'),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (callUri != null)
                              _ContactIconButton(
                                icon: Icons.call_outlined,
                                tooltip: 'Llamar cliente',
                                onTap: () => safeOpenUrl(context, callUri),
                                size: 36,
                              ),
                            if (whatsappUri != null)
                              _ContactIconButton(
                                icon: Icons.chat_bubble_outline_rounded,
                                tooltip: 'Escribir por WhatsApp',
                                onTap: () => safeOpenUrl(context, whatsappUri),
                                size: 36,
                              ),
                            if (locationUri != null)
                              _ContactIconButton(
                                icon: Icons.location_searching_rounded,
                                tooltip: 'Abrir GPS',
                                onTap: () => safeOpenUrl(context, locationUri),
                                size: 36,
                              ),
                          ],
                        ),
                        if (isTechnician) ...[
                          const SizedBox(height: 8),
                          _TechnicianQuickActionButton(order: order),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              priorityStyle.backgroundTint.withValues(alpha: 0.36),
              theme.colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.022),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: priorityStyle.borderColor.withValues(alpha: 0.48),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 34,
                      margin: const EdgeInsets.only(right: 8, top: 1),
                      decoration: BoxDecoration(
                        color: priorityStyle.edgeColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        hasCreatorName ? creatorCompactLabel : '---',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.2,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.12,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _buildRelativeTopLine(createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusBadge(status: order.status, compact: true),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.translate(
                            offset: const Offset(0, -1),
                            child: Text(
                              clientDisplayName.isEmpty
                                  ? 'Cliente sin nombre'
                                  : clientDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.1,
                                height: 1.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${order.serviceType.label} - ${order.category.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w400,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.12,
                                    height: 1,
                                  ),
                                ),
                              ),
                              if (serviceCityLabel != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  serviceCityLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.28,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MobileOrderActionsButton(
                      order: order,
                      statusBusy: statusBusy,
                      creatingNewOrder: creatingNewOrder,
                      canPromoteStatus: canPromoteStatus,
                      isTechnician: isTechnician,
                      callUri: callUri,
                      whatsappUri: whatsappUri,
                      locationUri: locationUri,
                      onCreateNewOrder: onCreateNewOrder,
                      onChangeStatus: onChangeStatus,
                      onEdit: onEdit,
                      onDelete: onDelete,
                    ),
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

class _ServiceTypePriorityStyle {
  const _ServiceTypePriorityStyle({
    required this.edgeColor,
    required this.borderColor,
    required this.backgroundTint,
  });

  final Color edgeColor;
  final Color borderColor;
  final Color backgroundTint;
}

_ServiceTypePriorityStyle _resolveServiceTypePriorityStyle(
  ServiceOrderType type,
) {
  switch (type) {
    case ServiceOrderType.instalacion:
      return const _ServiceTypePriorityStyle(
        edgeColor: Color(0xFFD97706),
        borderColor: Color(0xFFE7B15D),
        backgroundTint: Color(0xFFFFF4DB),
      );
    case ServiceOrderType.mantenimiento:
      return const _ServiceTypePriorityStyle(
        edgeColor: Color(0xFF1F8A5B),
        borderColor: Color(0xFF78C79E),
        backgroundTint: Color(0xFFEAF8F0),
      );
    case ServiceOrderType.levantamiento:
    case ServiceOrderType.garantia:
      return const _ServiceTypePriorityStyle(
        edgeColor: Color(0xFF8A94A6),
        borderColor: Color(0xFFD4DAE3),
        backgroundTint: Color(0xFFF6F8FB),
      );
  }
}

String? _extractServiceCity({String? address, String? locationUrl}) {
  final normalizedAddress = (address ?? '').trim();
  final candidates = <String>[
    if (normalizedAddress.isNotEmpty)
      ...normalizedAddress.split(RegExp(r'[,;|\-]')),
    if ((locationUrl ?? '').trim().isNotEmpty)
      ...Uri.decodeFull(locationUrl!.trim()).split(RegExp(r'[/,;|\-]')),
  ];

  const knownCities = <String>[
    'higuey',
    'higüey',
    'bavaro',
    'bávaro',
    'punta cana',
    'veron',
    'verón',
    'la romana',
    'santo domingo',
    'santiago',
    'san pedro de macoris',
    'san pedro de macorís',
    'bonao',
    'moca',
    'salvaleon de higuey',
    'salvaleón de higüey',
  ];

  for (final raw in candidates) {
    final chunk = raw.trim();
    if (chunk.isEmpty) continue;
    final lowered = chunk.toLowerCase();
    for (final city in knownCities) {
      if (lowered.contains(city)) {
        return city.toUpperCase().replaceAll('Ü', 'U');
      }
    }
  }

  if (normalizedAddress.isNotEmpty) {
    final parts = normalizedAddress
        .split(RegExp(r'[,;|]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      return parts.last.toUpperCase();
    }
  }

  return null;
}

String _compactCreatorLabel(String value) {
  final firstName = _extractFirstName(value).trim();
  if (firstName.isEmpty) {
    return '---';
  }
  return firstName.length <= 5 ? firstName : firstName.substring(0, 5);
}

String _buildRelativeTopLine(DateTime createdAt) {
  final localDate = createdAt.toLocal();
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfCreated = DateTime(
    localDate.year,
    localDate.month,
    localDate.day,
  );
  final dayDiff = startOfToday.difference(startOfCreated).inDays;
  final timeLabel = DateFormat('h:mm a', 'es_DO').format(localDate);

  if (dayDiff == 0) {
    return 'Hoy · $timeLabel';
  }
  if (dayDiff == 1) {
    return 'Ayer · $timeLabel';
  }
  final dateLabel = DateFormat('dd/MM/yy', 'es_DO').format(localDate);
  return '$dateLabel · $timeLabel';
}

class _MobileOrderActionsButton extends ConsumerWidget {
  const _MobileOrderActionsButton({
    required this.order,
    required this.statusBusy,
    required this.creatingNewOrder,
    required this.canPromoteStatus,
    required this.isTechnician,
    required this.callUri,
    required this.whatsappUri,
    required this.locationUri,
    this.onCreateNewOrder,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
  });

  final ServiceOrderModel order;
  final bool statusBusy;
  final bool creatingNewOrder;
  final bool canPromoteStatus;
  final bool isTechnician;
  final Uri? callUri;
  final Uri? whatsappUri;
  final Uri? locationUri;
  final VoidCallback? onCreateNewOrder;
  final ValueChanged<ServiceOrderStatus>? onChangeStatus;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final buttonKey = GlobalKey();
    return OutlinedButton(
      key: buttonKey,
      onPressed: () => _showActionsMenu(context, ref, buttonKey),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(92, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Text(
        'Acciones',
        style: theme.textTheme.labelMedium?.copyWith(
          fontSize: 11.6,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Future<void> _showActionsMenu(
    BuildContext context,
    WidgetRef ref,
    GlobalKey buttonKey,
  ) async {
    final selected = await showMenu<_OrderMenuAction>(
      context: context,
      position: _menuPositionFromButton(context, buttonKey),
      items: [
        if (onChangeStatus != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.changeStatus,
            child: _OrderMenuRow(
              icon: Icons.sync_alt_rounded,
              label: 'Cambiar estado',
              trailing: Icons.chevron_right_rounded,
            ),
          ),
        if (onCreateNewOrder != null)
          PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.newOrder,
            enabled: !creatingNewOrder,
            child: _OrderMenuRow(
              icon: Icons.add_circle_outline_rounded,
              label: creatingNewOrder ? 'Creando...' : 'Nueva orden',
            ),
          ),
        if (callUri != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.call,
            child: _OrderMenuRow(icon: Icons.call_outlined, label: 'Llamar'),
          ),
        if (whatsappUri != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.whatsapp,
            child: _OrderMenuRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'WhatsApp',
            ),
          ),
        if (locationUri != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.location,
            child: _OrderMenuRow(
              icon: Icons.location_on_outlined,
              label: 'Ubicación',
            ),
          ),
        if (onEdit != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.edit,
            child: _OrderMenuRow(icon: Icons.edit_outlined, label: 'Editar'),
          ),
        if (onDelete != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.delete,
            child: _OrderMenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Eliminar',
              destructive: true,
            ),
          ),
        if (isTechnician)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.technical,
            child: _OrderMenuRow(
              icon: Icons.tune_rounded,
              label: 'Gestión técnica',
            ),
          ),
      ],
    );

    if (selected == null || !context.mounted) {
      return;
    }

    switch (selected) {
      case _OrderMenuAction.changeStatus:
        await _showStatusSubmenu(context, buttonKey);
      case _OrderMenuAction.newOrder:
        if (!creatingNewOrder) {
          onCreateNewOrder?.call();
        }
      case _OrderMenuAction.call:
        if (callUri != null) {
          safeOpenUrl(context, callUri!);
        }
      case _OrderMenuAction.whatsapp:
        if (whatsappUri != null) {
          safeOpenUrl(context, whatsappUri!);
        }
      case _OrderMenuAction.location:
        if (locationUri != null) {
          safeOpenUrl(context, locationUri!);
        }
      case _OrderMenuAction.edit:
        onEdit?.call();
      case _OrderMenuAction.delete:
        onDelete?.call();
      case _OrderMenuAction.technical:
        await showServiceOrderQuickActionsModal(
          context: context,
          ref: ref,
          orderId: order.id,
          order: order,
          onOrderUpdated: () {
            ref.read(serviceOrdersListControllerProvider.notifier).refresh();
          },
        );
    }
  }

  Future<void> _showStatusSubmenu(
    BuildContext context,
    GlobalKey buttonKey,
  ) async {
    if (onChangeStatus == null) {
      return;
    }
    final selected = await showMenu<ServiceOrderStatus>(
      context: context,
      position: _menuPositionFromButton(context, buttonKey, dx: 128),
      items: ServiceOrderStatus.values
          .map(
            (status) => PopupMenuItem<ServiceOrderStatus>(
              value: status,
              enabled: !statusBusy && status != order.status,
              child: _OrderMenuRow(
                icon: status == order.status
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                label: status.label,
              ),
            ),
          )
          .toList(growable: false),
    );

    if (selected != null && selected != order.status && !statusBusy) {
      onChangeStatus?.call(selected);
    }
  }

  RelativeRect _menuPositionFromButton(
    BuildContext context,
    GlobalKey buttonKey, {
    double dx = 0,
  }) {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonBox =
        buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final offset = buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final left = offset.dx + dx;
    final top = offset.dy + buttonBox.size.height + 4;
    final right = overlayBox.size.width - (offset.dx + buttonBox.size.width);
    final bottom = overlayBox.size.height - top;
    return RelativeRect.fromLTRB(left, top, right, bottom);
  }
}

enum _OrderMenuAction {
  changeStatus,
  newOrder,
  call,
  whatsapp,
  location,
  edit,
  delete,
  technical,
}

class _OrderMenuRow extends StatelessWidget {
  const _OrderMenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool destructive;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = destructive ? colorScheme.error : colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, color: foreground, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null)
          Icon(trailing, size: 16, color: colorScheme.onSurfaceVariant),
      ],
    );
  }
}

class _DesktopInlineInfoChip extends StatelessWidget {
  const _DesktopInlineInfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopInfoBlock extends StatelessWidget {
  const _DesktopInfoBlock({
    required this.icon,
    required this.label,
    required this.primary,
    required this.secondary,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String primary;
  final String secondary;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveAccent = accent ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: effectiveAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 14, color: effectiveAccent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _compactOrderId(String rawId) {
  final normalized = rawId.trim();
  if (normalized.length <= 8) return normalized;
  return normalized.substring(0, 8).toUpperCase();
}

String _extractFirstName(String rawName) {
  final normalized = rawName.trim();
  if (normalized.isEmpty) return '';
  return normalized.split(RegExp(r'\s+')).first.trim();
}

String? _firstMeaningfulText(String? primary, String? secondary) {
  final candidates = [primary, secondary];
  for (final candidate in candidates) {
    final value = (candidate ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

class _PanelMetaPill extends StatelessWidget {
  const _PanelMetaPill({required this.icon, required this.text, this.accent});

  final IconData icon;
  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveAccent = accent ?? colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent == null
            ? colorScheme.surfaceContainerLowest
            : effectiveAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: effectiveAccent.withValues(
            alpha: accent == null ? 0.12 : 0.18,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: effectiveAccent),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
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
    required this.canPromoteStatus,
    required this.onSelected,
  });

  final ServiceOrderModel order;
  final bool busy;
  final bool canPromoteStatus;
  final ValueChanged<ServiceOrderStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    final nextStatuses = canPromoteStatus
        ? order.status.nextStatusesForRole(canFinalizeDirectly: true)
        : order.status.allowedNextStatuses
              .where((status) => status == ServiceOrderStatus.cancelado)
              .toList(growable: false);
    final statuses = [order.status, ...nextStatuses]
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
                                onTap: () =>
                                    Navigator.pop(sheetContext, status),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.55),
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
              Icon(Icons.check_circle_rounded, size: 18, color: status.color),
          ],
        ),
      ),
    );
  }
}

class _OrderActionsMenu extends StatelessWidget {
  const _OrderActionsMenu({
    required this.busy,
    required this.onEdit,
    this.onDelete,
  });

  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: !busy,
      tooltip: 'Acciones de la orden',
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined),
            title: Text('Editar'),
          ),
        ),
        if (onDelete != null)
          const PopupMenuItem<String>(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            final controller = ref.read(
              serviceOrdersListControllerProvider.notifier,
            );
            controller.refresh();
          },
        );
      },
    );
  }
}
