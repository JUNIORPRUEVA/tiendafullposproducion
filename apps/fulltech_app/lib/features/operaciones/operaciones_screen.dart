import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' hide ServiceStatus;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/models/punch_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/external_launcher.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_drawer.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../../modules/cotizaciones/cotizacion_models.dart';
import '../catalogo/catalogo_screen.dart';
import '../ponche/application/punch_controller.dart';
import '../user/data/users_repository.dart';
import 'application/operations_controller.dart';
import 'data/operations_repository.dart';
import 'operations_models.dart' hide ServiceStatus;
import 'operations_models.dart' as ops show ServiceStatus, parseStatus;
import 'presentation/service_agenda_card.dart';
import 'presentation/info_card.dart';
import 'presentation/operations_filters.dart';
import 'presentation/operations_permissions.dart';
import 'presentation/service_actions_sheet.dart';
import 'presentation/service_header.dart';
import 'presentation/service_location_helpers.dart';
import 'presentation/status_picker_sheet.dart';
import '../../modules/clientes/cliente_model.dart';

class OperacionesScreen extends ConsumerStatefulWidget {
  const OperacionesScreen({super.key});

  @override
  ConsumerState<OperacionesScreen> createState() => _OperacionesScreenState();
}

class _OperacionesScreenState extends ConsumerState<OperacionesScreen>
    with WidgetsBindingObserver {
  static const double _desktopOperationsBreakpoint = kDesktopShellBreakpoint;
  static const Duration _deepLinkTimeout = Duration(seconds: 12);

  final _searchCtrl = TextEditingController();
  String? _lastAppliedDeepLinkKey;

  Future<void> _openQuickCreateFromAppBar() async {
    const title = 'Crear orden de servicio';
    const submitLabel = 'Guardar orden';
    const initialServiceType = 'maintenance';

    var orderType = 'mantenimiento';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.92,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        'Crea una orden genérica. La etapa se puede ajustar luego en Detalles.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('quick-create-orderType-$orderType'),
                        initialValue: orderType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Fase de orden',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'reserva',
                            child: Text('Reserva'),
                          ),
                          DropdownMenuItem(
                            value: 'instalacion',
                            child: Text('Instalación'),
                          ),
                          DropdownMenuItem(
                            value: 'mantenimiento',
                            child: Text('Mantenimiento'),
                          ),
                          DropdownMenuItem(
                            value: 'garantia',
                            child: Text('Garantía'),
                          ),
                          DropdownMenuItem(
                            value: 'levantamiento',
                            child: Text('Levantamiento'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => orderType = value);
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _CreateReservationTab(
                        onCreate: (draft) async {
                          final ok = await _handleCreateGenericOrder(
                            draft,
                            orderType: orderType,
                          );
                          if (ok && context.mounted) Navigator.pop(context);
                        },
                        submitLabel: submitLabel,
                        initialServiceType: initialServiceType,
                        showServiceTypeField: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _agendaPlusIcon() {
    return const Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.event_note_rounded),
        Positioned(
          right: -2,
          top: -2,
          child: Icon(Icons.add_circle_outline, size: 14),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final qp = GoRouterState.of(context).uri.queryParameters;
    final customerId = (qp['customerId'] ?? '').trim();
    final serviceId = (qp['serviceId'] ?? '').trim();

    if (customerId.isEmpty && serviceId.isEmpty) return;

    final key = '$customerId|$serviceId';
    if (_lastAppliedDeepLinkKey == key) return;
    _lastAppliedDeepLinkKey = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_applyDeepLink(customerId: customerId, serviceId: serviceId));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      ref.read(operationsControllerProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyDeepLink({
    required String customerId,
    required String serviceId,
  }) async {
    final notifier = ref.read(operationsControllerProvider.notifier);

    try {
      if (customerId.trim().isNotEmpty) {
        await notifier.setCustomer(customerId.trim());
      }

      if (!mounted) return;

      if (serviceId.trim().isNotEmpty) {
        final targetId = serviceId.trim();

        final currentState = ref.read(operationsControllerProvider);
        ServiceModel? fromList;
        for (final item in currentState.services) {
          if (item.id.trim() == targetId) {
            fromList = item;
            break;
          }
        }

        final service =
            fromList ??
            await notifier.getOne(targetId).timeout(_deepLinkTimeout);
        if (!mounted) return;
        await _openServiceDetail(service);
      }
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : 'No se pudo abrir el proceso automáticamente.';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _changeStatusWithConfirm(ServiceModel service) async {
    final statuses = const [
      'reserved',
      'survey',
      'scheduled',
      'in_progress',
      'completed',
      'warranty',
      'closed',
      'cancelled',
    ];

    String label(String raw) {
      switch (raw) {
        case 'reserved':
          return 'Reserva';
        case 'survey':
          return 'Levantamiento';
        case 'scheduled':
          return 'Servicio (agendado)';
        case 'in_progress':
          return 'Servicio (en proceso)';
        case 'warranty':
          return 'Garantía';
        case 'completed':
          return 'Finalizado';
        case 'closed':
          return 'Cerrado';
        case 'cancelled':
          return 'Cancelado';
        default:
          return raw;
      }
    }

    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Cambiar estado'),
          children: statuses
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Row(
                    children: [
                      Expanded(child: Text(label(s))),
                      if (s == service.status)
                        const Icon(Icons.check_rounded, size: 18),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );

    if (!mounted || picked == null) return;
    if (picked == service.status) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cambio'),
          content: Text(
            'Vas a cambiar el estado de "${label(service.status)}" a "${label(picked)}".\n\n¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cambiar'),
            ),
          ],
        );
      },
    );
    if (!mounted || ok != true) return;

    await _changeStatus(service.id, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Estado cambiado a ${label(picked)}')),
    );
  }

  Future<void> _openCatalogoDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.80,
          child: const CatalogoScreen(modal: true),
        ),
      ),
    );
  }

  Future<void> _openPoncheDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.60,
          child: const _PunchOnlySheet(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar({
    required AuthState authState,
    required Color gradientTop,
    required Color gradientMid,
    required Color gradientBottom,
  }) {
    return AppBar(
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'Operaciones',
          maxLines: 1,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradientTop, gradientMid, gradientBottom],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => context.go(Routes.operacionesReglas),
          icon: const Icon(Icons.rule_folder_outlined),
          label: const Text('Reglas'),
        ),
        IconButton(
          tooltip: 'Agregar orden',
          onPressed: _openQuickCreateFromAppBar,
          icon: _agendaPlusIcon(),
        ),
        IconButton(
          tooltip: 'Mapa clientes',
          onPressed: () => context.push(Routes.operacionesMapaClientes),
          icon: const Icon(Icons.map_outlined),
        ),
        _UserAvatarAction(
          userName: authState.user?.nombreCompleto,
          photoUrl: authState.user?.fotoPersonalUrl,
          onTap: () => context.go(Routes.profile),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  PreferredSizeWidget _buildDesktopAppBar({
    required BuildContext context,
    required AuthState authState,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateFormat('EEEE, d MMMM yyyy', 'es').format(DateTime.now());

    return AppBar(
      toolbarHeight: 78,
      elevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleSpacing: 18,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Centro de Operaciones',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            today,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => context.go(Routes.operacionesReglas),
          icon: const Icon(Icons.rule_folder_outlined),
          label: const Text('Reglas'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _openQuickCreateFromAppBar,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Nueva orden'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Mapa clientes',
          onPressed: () => context.push(Routes.operacionesMapaClientes),
          icon: const Icon(Icons.map_outlined),
        ),
        const SizedBox(width: 8),
        _UserAvatarAction(
          userName: authState.user?.nombreCompleto,
          photoUrl: authState.user?.fotoPersonalUrl,
          onTap: () => context.go(Routes.profile),
        ),
        const SizedBox(width: 14),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _buildDesktopFabDock() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FilledButton.tonalIcon(
              onPressed: _openCatalogoDialog,
              icon: const _CatalogoFabIcon(),
              label: const Text('Catálogo'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _openPoncheDialog,
              icon: const _PoncheFabIcon(),
              label: const Text('Ponche'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final state = ref.watch(operationsControllerProvider);
    final notifier = ref.read(operationsControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= _desktopOperationsBreakpoint;

    final gradientTop = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.10),
      scheme.primary,
    );
    final gradientMid = Color.alphaBlend(
      scheme.secondary.withValues(alpha: 0.16),
      scheme.primary,
    );
    final gradientBottom = Color.alphaBlend(
      scheme.tertiary.withValues(alpha: 0.18),
      scheme.primary,
    );

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: authState.user),
      appBar: isDesktop
          ? _buildDesktopAppBar(context: context, authState: authState)
          : _buildMobileAppBar(
              authState: authState,
              gradientTop: gradientTop,
              gradientMid: gradientMid,
              gradientBottom: gradientBottom,
            ),
      floatingActionButton: isDesktop
          ? _buildDesktopFabDock()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab-catalogo',
                  tooltip: 'Catálogo',
                  onPressed: _openCatalogoDialog,
                  child: const _CatalogoFabIcon(),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'fab-ponche',
                  tooltip: 'Ponche',
                  onPressed: _openPoncheDialog,
                  child: const _PoncheFabIcon(),
                ),
              ],
            ),
      body: Stack(
        children: [
          _buildBoard(context, authState.user, state, notifier),
          if (state.loading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoard(
    BuildContext context,
    UserModel? currentUser,
    OperationsState state,
    OperationsController notifier,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      child: _PanelOptions(
        currentUser: currentUser,
        state: state,
        searchCtrl: _searchCtrl,
        onRefresh: notifier.refresh,
        loadUsers: () => ref.read(usersRepositoryProvider).getAllUsers(),
        loadTechnicians: () =>
            ref.read(operationsRepositoryProvider).getTechnicians(),
        onApplyRemote: (range, techId) => notifier.applyRangeAndTechnician(
          from: range.start,
          to: range.end,
          technicianId: (techId ?? '').trim().isEmpty ? null : techId,
        ),
        onOpenService: _openServiceDetail,
        onChangeStatus: _changeStatusWithConfirm,
        onChangeOrderState: (serviceId, orderState) =>
            notifier.changeOrderStateOptimistic(serviceId, orderState),
        onChangeAdminPhase: (serviceId, adminPhase) =>
            notifier.changeAdminPhaseOptimistic(serviceId, adminPhase),
        onChangePhase: (service, phase, scheduledAt, note) =>
            notifier.changePhaseOptimistic(
              service.id,
              phase,
              scheduledAt: scheduledAt,
              note: note,
            ),
      ),
    );
  }

  Future<void> _openServiceDetail(ServiceModel service) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: _ServiceDetailPanel(
              service: service,
              onChangeStatus: (status) => _changeStatus(service.id, status),
              onChangeOrderState: (orderState) => ref
                  .read(operationsControllerProvider.notifier)
                  .changeOrderStateOptimistic(service.id, orderState),
              onChangeAdminPhase: (adminPhase) => ref
                  .read(operationsControllerProvider.notifier)
                  .changeAdminPhaseOptimistic(service.id, adminPhase),
              onSchedule: (start, end) =>
                  _scheduleService(service.id, start, end),
              onCreateWarranty: () => _createWarranty(service.id),
              onAssign: (assignments) => _assignTechs(service.id, assignments),
              onToggleStep: (stepId, done) =>
                  _toggleStep(service.id, stepId, done),
              onAddNote: (message) => _addNote(service.id, message),
              onUploadEvidence: () => _uploadEvidence(service.id),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Future<void> _handleCreateService(_CreateServiceDraft draft) async {
    try {
      final created = await _createService(draft);

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ApiException ? e.message : 'No se pudo agendar la reserva',
              ),
            ),
          );
        }
      }

      final referencePhoto = draft.referencePhoto;
      if (referencePhoto != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .uploadEvidence(created.id, referencePhoto);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ApiException
                    ? e.message
                    : 'No se pudo subir la foto de referencia',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reserva creada correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar el servicio',
          ),
        ),
      );
    }
  }

  Future<ServiceModel> _createService(
    _CreateServiceDraft draft, {
    String? orderType,
  }) {
    return ref
        .read(operationsControllerProvider.notifier)
        .createReservation(
          customerId: draft.customerId,
          serviceType: draft.serviceType,
          category: draft.category,
          priority: draft.priority,
          title: draft.title,
          description: draft.description,
          addressSnapshot: draft.addressSnapshot,
          quotedAmount: draft.quotedAmount,
          depositAmount: draft.depositAmount,
          orderType: orderType,
          orderState: draft.orderState,
          technicianId: draft.technicianId,
          warrantyParentServiceId: draft.relatedServiceId,
          surveyResult: draft.surveyResult,
          materialsUsed: draft.materialsUsed,
          finalCost: draft.finalCost,
          tags: draft.tags,
        );
  }

  Future<bool> _handleCreateGenericOrder(
    _CreateServiceDraft draft, {
    required String orderType,
  }) async {
    final normalized = orderType.trim().isEmpty
        ? 'mantenimiento'
        : orderType.trim().toLowerCase();

    try {
      final created = await _createService(draft, orderType: normalized);

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación.
        }

        // Si está agendada, por defecto marca la etapa como agendada.
        if (created.status.trim().toLowerCase() != 'scheduled') {
          try {
            await ref
                .read(operationsControllerProvider.notifier)
                .changeStatus(created.id, 'scheduled');
          } catch (_) {
            // No bloquea la creación.
          }
        }
      }

      final referencePhoto = draft.referencePhoto;
      if (referencePhoto != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .uploadEvidence(created.id, referencePhoto);
        } catch (_) {
          // No bloquea la creación.
        }
      }

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden creada correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar la orden',
          ),
        ),
      );
      return false;
    }
  }

  // ignore: unused_element
  Future<bool> _handleCreateFromAgenda(
    _CreateServiceDraft draft,
    String kind,
  ) async {
    final lower = kind.trim().toLowerCase();
    final targetStatus = switch (lower) {
      'levantamiento' => 'survey',
      'servicio' => 'scheduled',
      'mantenimiento' => 'scheduled',
      'instalacion' => 'scheduled',
      'garantia' => 'warranty',
      _ => null,
    };
    final successLabel = switch (lower) {
      'reserva' => 'Reserva',
      'levantamiento' => 'Levantamiento',
      'servicio' => 'Mantenimiento',
      'mantenimiento' => 'Mantenimiento',
      'instalacion' => 'Instalación',
      'garantia' => 'Garantía',
      _ => 'Servicio',
    };

    try {
      final created = await _createService(draft, orderType: lower);

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación desde agenda.
        }
      }

      final referencePhoto = draft.referencePhoto;
      if (referencePhoto != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .uploadEvidence(created.id, referencePhoto);
        } catch (_) {
          // No bloquea la creación desde agenda.
        }
      }

      if (targetStatus != null && targetStatus != created.status) {
        await ref
            .read(operationsControllerProvider.notifier)
            .changeStatus(created.id, targetStatus);
      }
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successLabel creado correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar el servicio',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _changeStatus(String serviceId, String status) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .changeStatus(serviceId, status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _scheduleService(String id, DateTime start, DateTime end) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .schedule(id, start, end);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _createWarranty(String id) async {
    try {
      await ref.read(operationsControllerProvider.notifier).createWarranty(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _toggleStep(String id, String stepId, bool done) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .toggleStep(id, stepId, done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _addNote(String id, String note) async {
    try {
      await ref.read(operationsControllerProvider.notifier).addNote(id, note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _assignTechs(
    String id,
    List<Map<String, String>> assignments,
  ) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .assign(id, assignments);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _uploadEvidence(String id) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .uploadEvidence(id, result.files.first);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evidencia subida')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }
}

class OperacionesAgendaScreen extends ConsumerStatefulWidget {
  const OperacionesAgendaScreen({super.key});

  @override
  ConsumerState<OperacionesAgendaScreen> createState() =>
      _OperacionesAgendaScreenState();
}

class _OperacionesAgendaScreenState
    extends ConsumerState<OperacionesAgendaScreen> {
  // ignore: unused_element
  String _statusLabel(String raw) {
    switch (raw) {
      case 'reserved':
        return 'Sin etapa';
      case 'survey':
        return 'Levantamiento';
      case 'scheduled':
        return 'Agendado';
      case 'in_progress':
        return 'En proceso';
      case 'warranty':
        return 'Garantía';
      case 'completed':
        return 'Finalizado';
      case 'closed':
        return 'Cerrado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return raw;
    }
  }

  String _serviceTypeLabel(String raw) {
    switch (raw) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Servicio técnico';
      case 'warranty':
        return 'Garantía';
      default:
        return raw;
    }
  }

  String _categoryLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cameras':
        return 'Cámaras';
      case 'gate_motor':
        return 'Motores de puertones';
      case 'alarm':
        return 'Alarma';
      case 'electric_fence':
        return 'Cerco eléctrico';
      case 'intercom':
        return 'Intercom';
      case 'pos':
        return 'Punto de ventas';
      default:
        return raw.trim().isEmpty ? 'General' : raw.trim();
    }
  }

  Future<void> _openServiceDetail(ServiceModel service) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: _ServiceDetailPanel(
              service: service,
              onChangeStatus: (status) => _changeStatus(service.id, status),
              onChangeOrderState: (orderState) => ref
                  .read(operationsControllerProvider.notifier)
                  .changeOrderStateOptimistic(service.id, orderState),
              onChangeAdminPhase: (adminPhase) => ref
                  .read(operationsControllerProvider.notifier)
                  .changeAdminPhaseOptimistic(service.id, adminPhase),
              onSchedule: (start, end) =>
                  _scheduleService(service.id, start, end),
              onCreateWarranty: () => _createWarranty(service.id),
              onAssign: (assignments) => _assignTechs(service.id, assignments),
              onToggleStep: (stepId, done) =>
                  _toggleStep(service.id, stepId, done),
              onAddNote: (message) => _addNote(service.id, message),
              onUploadEvidence: () => _uploadEvidence(service.id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _changeStatusWithConfirm(ServiceModel service) async {
    final statuses = const [
      'reserved',
      'survey',
      'scheduled',
      'in_progress',
      'completed',
      'warranty',
      'closed',
      'cancelled',
    ];

    String label(String raw) {
      switch (raw) {
        case 'reserved':
          return 'Reserva';
        case 'survey':
          return 'Levantamiento';
        case 'scheduled':
          return 'Servicio (agendado)';
        case 'in_progress':
          return 'Servicio (en proceso)';
        case 'warranty':
          return 'Garantía';
        case 'completed':
          return 'Finalizado';
        case 'closed':
          return 'Cerrado';
        case 'cancelled':
          return 'Cancelado';
        default:
          return raw;
      }
    }

    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Cambiar estado'),
          children: statuses
              .map(
                (s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, s),
                  child: Row(
                    children: [
                      Expanded(child: Text(label(s))),
                      if (s == service.status)
                        const Icon(Icons.check_rounded, size: 18),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );

    if (!mounted || picked == null) return;
    if (picked == service.status) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cambio'),
          content: Text(
            'Vas a cambiar el estado de "${label(service.status)}" a "${label(picked)}".\n\n¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cambiar'),
            ),
          ],
        );
      },
    );
    if (!mounted || ok != true) return;

    await _changeStatus(service.id, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Estado cambiado a ${label(picked)}')),
    );
  }

  Future<void> _changeStatus(String serviceId, String status) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .changeStatus(serviceId, status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _scheduleService(String id, DateTime start, DateTime end) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .schedule(id, start, end);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _createWarranty(String id) async {
    try {
      await ref.read(operationsControllerProvider.notifier).createWarranty(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _toggleStep(String id, String stepId, bool done) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .toggleStep(id, stepId, done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _addNote(String id, String note) async {
    try {
      await ref.read(operationsControllerProvider.notifier).addNote(id, note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _assignTechs(
    String id,
    List<Map<String, String>> assignments,
  ) async {
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .assign(id, assignments);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _uploadEvidence(String id) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .uploadEvidence(id, result.files.first);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Evidencia subida')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  // ignore: unused_element
  Future<bool> _createFromAgenda(_CreateServiceDraft draft, String kind) async {
    final lower = kind.trim().toLowerCase();
    final targetStatus = switch (lower) {
      'levantamiento' => 'survey',
      'servicio' => 'scheduled',
      'garantia' => 'warranty',
      _ => null,
    };
    final successLabel = switch (lower) {
      'reserva' => 'Reserva',
      'levantamiento' => 'Levantamiento',
      'servicio' => 'Servicio',
      'garantia' => 'Garantía',
      _ => 'Servicio',
    };

    try {
      final created = await ref
          .read(operationsControllerProvider.notifier)
          .createReservation(
            customerId: draft.customerId,
            serviceType: draft.serviceType,
            category: draft.category,
            priority: draft.priority,
            title: draft.title,
            description: draft.description,
            addressSnapshot: draft.addressSnapshot,
            quotedAmount: draft.quotedAmount,
            depositAmount: draft.depositAmount,
            orderType: lower,
            orderState: draft.orderState,
            technicianId: draft.technicianId,
            warrantyParentServiceId: draft.relatedServiceId,
            surveyResult: draft.surveyResult,
            materialsUsed: draft.materialsUsed,
            finalCost: draft.finalCost,
            tags: draft.tags,
          );

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación desde agenda.
        }
      }

      final referencePhoto = draft.referencePhoto;
      if (referencePhoto != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .uploadEvidence(created.id, referencePhoto);
        } catch (e) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ApiException
                    ? e.message
                    : 'No se pudo subir la foto de referencia',
              ),
            ),
          );
        }
      }

      if (targetStatus != null && targetStatus != created.status) {
        await ref
            .read(operationsControllerProvider.notifier)
            .changeStatus(created.id, targetStatus);
      }

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$successLabel creado correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar el servicio',
          ),
        ),
      );
      return false;
    }
  }

  Future<bool> _createGenericFromAgenda(_CreateServiceDraft draft) async {
    const orderType = 'mantenimiento';

    try {
      final created = await ref
          .read(operationsControllerProvider.notifier)
          .createReservation(
            customerId: draft.customerId,
            serviceType: draft.serviceType,
            category: draft.category,
            priority: draft.priority,
            title: draft.title,
            description: draft.description,
            addressSnapshot: draft.addressSnapshot,
            quotedAmount: draft.quotedAmount,
            depositAmount: draft.depositAmount,
            orderType: orderType,
            orderState: draft.orderState,
            technicianId: draft.technicianId,
            warrantyParentServiceId: draft.relatedServiceId,
            surveyResult: draft.surveyResult,
            materialsUsed: draft.materialsUsed,
            finalCost: draft.finalCost,
            tags: draft.tags,
          );

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
        } catch (_) {
          // No bloquea la creación desde agenda.
        }

        if (created.status.trim().toLowerCase() != 'scheduled') {
          try {
            await ref
                .read(operationsControllerProvider.notifier)
                .changeStatus(created.id, 'scheduled');
          } catch (_) {
            // No bloquea la creación desde agenda.
          }
        }
      }

      final referencePhoto = draft.referencePhoto;
      if (referencePhoto != null) {
        try {
          await ref
              .read(operationsControllerProvider.notifier)
              .uploadEvidence(created.id, referencePhoto);
        } catch (e) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ApiException
                    ? e.message
                    : 'No se pudo subir la foto de referencia',
              ),
            ),
          );
        }
      }

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden creada correctamente')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo registrar la orden',
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _openAgendaForm() async {
    const title = 'Crear orden de servicio';
    const submitLabel = 'Guardar orden';
    const initialServiceType = 'maintenance';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.92,
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Text(
                          'Crea una orden genérica. La etapa se puede ajustar luego en Detalles.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _CreateReservationTab(
                          submitLabel: submitLabel,
                          initialServiceType: initialServiceType,
                          showServiceTypeField: false,
                          onCreate: (draft) async {
                            final ok = await _createGenericFromAgenda(draft);
                            if (ok && context.mounted) Navigator.pop(context);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHistorialDialog(List<ServiceModel> services) async {
    final items = [...services];
    items.sort((a, b) {
      final ad = a.scheduledStart ?? a.completedAt;
      final bd = b.scheduledStart ?? b.completedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Historial de servicios (${items.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('Sin servicios para mostrar'),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final service = items[index];
                              final date =
                                  service.scheduledStart ?? service.completedAt;
                              final dateText = date == null
                                  ? '—'
                                  : df.format(date);
                              return ListTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${service.customerName} · ${service.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (service.isSeguro) ...[
                                      const SizedBox(width: 8),
                                      const _SeguroBadge(),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  '$dateText · ${service.status} · ${service.serviceType} · P${service.priority}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(operationsControllerProvider);
    final notifier = ref.read(operationsControllerProvider.notifier);

    final scheduled =
        state.services.where((s) => s.scheduledStart != null).toList()
          ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final router = GoRouter.of(context);
            if (router.canPop()) {
              router.pop();
              return;
            }
            context.go(Routes.operaciones);
          },
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Agenda',
            maxLines: 1,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Historial',
            onPressed: () => _openHistorialDialog(state.services),
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agendar',
        onPressed: _openAgendaForm,
        child: const Icon(Icons.add_rounded),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: notifier.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.event_note_rounded),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Agenda de servicios',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text('${scheduled.length}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (scheduled.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('Sin servicios agendados'),
                      ),
                    )
                  else
                    ...scheduled.map((service) {
                      final typeText = _serviceTypeLabel(service.serviceType);
                      final categoryText = _categoryLabel(service.category);
                      final address = service.customerAddress.trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openServiceDetail(service),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          service.customerName.trim().isEmpty
                                              ? 'Cliente'
                                              : service.customerName.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Cambiar estado',
                                        onPressed: () =>
                                            _changeStatusWithConfirm(service),
                                        icon: const Icon(
                                          Icons.swap_horiz_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    categoryText.isEmpty
                                        ? typeText
                                        : '$typeText · $categoryText',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 16,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          address.isEmpty
                                              ? 'Sin dirección'
                                              : address,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.70),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _UserAvatarAction extends StatelessWidget {
  final String? userName;
  final String? photoUrl;
  final VoidCallback onTap;

  const _UserAvatarAction({
    required this.userName,
    required this.photoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = getInitials((userName ?? 'Usuario').trim());
    final trimmedUrl = photoUrl?.trim() ?? '';

    Widget avatar;
    if (trimmedUrl.isNotEmpty) {
      avatar = ClipOval(
        child: Image.network(
          trimmedUrl,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _InitialsAvatar(initials: initials);
          },
        ),
      );
    } else {
      avatar = _InitialsAvatar(initials: initials);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Tooltip(
          message: 'Mi perfil',
          child: Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(
                color: scheme.onPrimary.withValues(alpha: 0.22),
              ),
            ),
            child: Center(child: avatar),
          ),
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;

  const _InitialsAvatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.white.withValues(alpha: 0.20),
      child: Text(
        initials.isEmpty ? 'U' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SeguroBadge extends StatelessWidget {
  const _SeguroBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.30)),
      ),
      child: Text(
        'SEGURO',
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

bool _looksLikeValidLocationText(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  if (RegExp(r'https?://', caseSensitive: false).hasMatch(v)) return true;
  if (parseLatLngFromText(v) != null) return true;
  final compact = v.replaceAll(RegExp(r'\s+'), ' ').trim();
  return compact.length >= 8;
}

bool _isFinalizedService(ServiceModel s) {
  final orderState = s.orderState.trim().toLowerCase();
  final status = s.status.trim().toLowerCase();
  if (orderState == 'finalized') return true;
  if (status == 'completed' || status == 'closed') return true;
  return false;
}

List<String> _missingPhaseRequirements(ServiceModel s, String phase) {
  final p = phase.trim().toLowerCase();

  if (p == 'instalacion' || p == 'mantenimiento' || p == 'levantamiento') {
    final missing = <String>[];
    final quoted = (s.quotedAmount ?? 0);
    final total = (s.finalCost ?? 0);
    if (quoted <= 0) missing.add('Cotización');
    if (total <= 0) missing.add('Monto total');
    if (!_looksLikeValidLocationText(s.customerAddress)) {
      missing.add('Ubicación');
    }
    return missing;
  }

  if (p == 'garantia') {
    final missing = <String>[];
    if (!_isFinalizedService(s)) missing.add('Orden finalizada');
    return missing;
  }

  return const [];
}

class _PanelOptions extends StatefulWidget {
  final UserModel? currentUser;
  final OperationsState state;
  final TextEditingController searchCtrl;
  final Future<void> Function() onRefresh;

  final Future<List<UserModel>> Function() loadUsers;
  final Future<List<TechnicianModel>> Function() loadTechnicians;
  final Future<void> Function(DateTimeRange range, String? technicianId)
  onApplyRemote;

  final void Function(ServiceModel) onOpenService;
  final Future<void> Function(ServiceModel service) onChangeStatus;
  final Future<void> Function(String serviceId, String orderState)
  onChangeOrderState;
  final Future<void> Function(String serviceId, String adminPhase)
  onChangeAdminPhase;
  final Future<void> Function(
    ServiceModel service,
    String phase,
    DateTime scheduledAt,
    String? note,
  )
  onChangePhase;

  const _PanelOptions({
    required this.currentUser,
    required this.state,
    required this.searchCtrl,
    required this.onRefresh,
    required this.loadUsers,
    required this.loadTechnicians,
    required this.onApplyRemote,
    required this.onOpenService,
    required this.onChangeStatus,
    required this.onChangeOrderState,
    required this.onChangeAdminPhase,
    required this.onChangePhase,
  });

  @override
  State<_PanelOptions> createState() => _PanelOptionsState();
}

class _PanelOptionsState extends State<_PanelOptions> {
  OperationsFilters _filters = OperationsFilters.todayDefault();

  Future<List<UserModel>>? _usersFuture;
  Future<List<TechnicianModel>>? _techsFuture;

  @override
  void initState() {
    super.initState();
    _filters = OperationsFilters.todayDefault();
    widget.searchCtrl.addListener(_onQueryChange);
  }

  @override
  void didUpdateWidget(covariant _PanelOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchCtrl != widget.searchCtrl) {
      oldWidget.searchCtrl.removeListener(_onQueryChange);
      widget.searchCtrl.addListener(_onQueryChange);
    }
  }

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_onQueryChange);
    super.dispose();
  }

  void _onQueryChange() {
    if (mounted) setState(() {});
  }

  String _rangeLabel(DateTimeRange r) {
    final df = DateFormat('dd/MM/yyyy', 'es');
    if (r.start.year == r.end.year &&
        r.start.month == r.end.month &&
        r.start.day == r.end.day) {
      return 'Hoy, ${df.format(r.start)}';
    }
    return '${df.format(r.start)} - ${df.format(r.end)}';
  }

  // ignore: unused_element
  bool _isDefaultTodayRange(DateTimeRange r) {
    final today = OperationsFilters.todayDefault().range;
    return r.start == today.start && r.end == today.end;
  }

  // ignore: unused_element
  InputDecoration _denseDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      isDense: true,
      prefixIcon: Icon(icon),
      hintText: hint,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _choiceChips<T>({
    required T value,
    required List<(T, String)> items,
    required void Function(T next) onChanged,
  }) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final it in items)
          ChoiceChip(
            label: Text(
              it.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            selected: value == it.$1,
            onSelected: (_) => onChanged(it.$1),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
      ],
    );
  }

  Future<String?> _pickFromListSheet({
    required String title,
    required List<(String id, String label)> items,
    required String? selectedId,
  }) {
    return showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        String query = '';

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        List<(String id, String label)> filtered() {
          final q = query.trim().toLowerCase();
          if (q.isEmpty) return items;
          return items.where((e) => e.$2.toLowerCase().contains(q)).toList();
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setInner) {
                final list = filtered();

                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Buscar…',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (v) => setInner(() => query = v),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.all_inclusive,
                                color: scheme.primary,
                              ),
                              title: const Text(
                                'Todos',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              trailing: selectedId == null
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: scheme.primary,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, null),
                            ),
                            const Divider(height: 1),
                            for (final e in list)
                              ListTile(
                                title: Text(
                                  e.$2,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                trailing: selectedId == e.$1
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: scheme.primary,
                                      )
                                    : null,
                                onTap: () => Navigator.pop(context, e.$1),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openFilters() async {
    _usersFuture ??= widget.loadUsers();
    _techsFuture ??= widget.loadTechnicians();

    OperationsFilters draft = _filters;
    final hasCancelled = widget.state.services.any(
      (s) => s.status.trim().toLowerCase() == 'cancelled',
    );
    final hasLowPriority = widget.state.services.any((s) => s.priority >= 3);

    final result = await showModalBottomSheet<OperationsFilters>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.80,
            minChildSize: 0.70,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return StatefulBuilder(
                builder: (context, setSheetState) {
                  Future<void> pickCustomRange() async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: draft.range,
                      helpText: 'Selecciona intervalo de fecha',
                    );
                    if (picked == null) return;
                    setSheetState(() => draft = draft.withCustomRange(picked));
                  }

                  Widget header() {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Filtros',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    );
                  }

                  Widget footer() {
                    final scheme = theme.colorScheme;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        border: Border(
                          top: BorderSide(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setSheetState(
                                  () =>
                                      draft = OperationsFilters.todayDefault(),
                                );
                              },
                              child: const Text('Limpiar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(context, draft),
                              child: const Text('Aplicar'),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Material(
                    color: theme.colorScheme.surface,
                    child: Column(
                      children: [
                        const SizedBox(height: 6),
                        header(),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            children: [
                              _sectionCard(
                                title: 'Usuario creador',
                                child: FutureBuilder<List<UserModel>>(
                                  future: _usersFuture,
                                  builder: (context, snap) {
                                    if (snap.connectionState !=
                                        ConnectionState.done) {
                                      return const LinearProgressIndicator();
                                    }
                                    if (snap.hasError) {
                                      return Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'No se pudieron cargar usuarios',
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              setSheetState(() {
                                                _usersFuture = widget
                                                    .loadUsers();
                                              });
                                            },
                                            child: const Text('Reintentar'),
                                          ),
                                        ],
                                      );
                                    }

                                    final users =
                                        (snap.data ?? const [])
                                            .where(
                                              (u) =>
                                                  (u.blocked) == false &&
                                                  u.id.trim().isNotEmpty,
                                            )
                                            .toList()
                                          ..sort(
                                            (a, b) => a.nombreCompleto
                                                .toLowerCase()
                                                .compareTo(
                                                  b.nombreCompleto
                                                      .toLowerCase(),
                                                ),
                                          );

                                    final selectedId = draft.createdByUserId;
                                    final selectedLabel = selectedId == null
                                        ? 'Todos'
                                        : (users
                                                  .firstWhere(
                                                    (u) => u.id == selectedId,
                                                    orElse: () => users.first,
                                                  )
                                                  .nombreCompleto)
                                              .trim();

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.badge_outlined),
                                      title: Text(
                                        selectedLabel.isEmpty
                                            ? 'Todos'
                                            : selectedLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right_rounded,
                                      ),
                                      onTap: () async {
                                        final items = users
                                            .map(
                                              (u) => (
                                                u.id,
                                                u.nombreCompleto.trim().isEmpty
                                                    ? (u.email.trim().isEmpty
                                                          ? 'Usuario'
                                                          : u.email.trim())
                                                    : u.nombreCompleto.trim(),
                                              ),
                                            )
                                            .toList(growable: false);

                                        final picked = await _pickFromListSheet(
                                          title: 'Usuario creador',
                                          items: items,
                                          selectedId: selectedId,
                                        );
                                        if (picked == null) {
                                          setSheetState(
                                            () => draft = draft.copyWith(
                                              clearCreatedBy: true,
                                            ),
                                          );
                                          return;
                                        }

                                        setSheetState(
                                          () => draft = draft.copyWith(
                                            createdByUserId: picked,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),
                              _sectionCard(
                                title: 'Técnico asignado',
                                child: FutureBuilder<List<TechnicianModel>>(
                                  future: _techsFuture,
                                  builder: (context, snap) {
                                    if (snap.connectionState !=
                                        ConnectionState.done) {
                                      return const LinearProgressIndicator();
                                    }
                                    if (snap.hasError) {
                                      return Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'No se pudieron cargar técnicos',
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              setSheetState(() {
                                                _techsFuture = widget
                                                    .loadTechnicians();
                                              });
                                            },
                                            child: const Text('Reintentar'),
                                          ),
                                        ],
                                      );
                                    }

                                    final techs =
                                        (snap.data ?? const [])
                                            .where(
                                              (t) => t.id.trim().isNotEmpty,
                                            )
                                            .toList()
                                          ..sort(
                                            (a, b) =>
                                                a.name.toLowerCase().compareTo(
                                                  b.name.toLowerCase(),
                                                ),
                                          );

                                    final selectedId = draft.technicianId;
                                    final selectedLabel = selectedId == null
                                        ? 'Todos'
                                        : (techs
                                                  .firstWhere(
                                                    (t) => t.id == selectedId,
                                                    orElse: () => techs.first,
                                                  )
                                                  .name)
                                              .trim();

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.engineering_outlined,
                                      ),
                                      title: Text(
                                        selectedLabel.isEmpty
                                            ? 'Todos'
                                            : selectedLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right_rounded,
                                      ),
                                      onTap: () async {
                                        final items = techs
                                            .map(
                                              (t) => (
                                                t.id,
                                                t.name.trim().isEmpty
                                                    ? 'Técnico'
                                                    : t.name.trim(),
                                              ),
                                            )
                                            .toList(growable: false);

                                        final picked = await _pickFromListSheet(
                                          title: 'Técnico asignado',
                                          items: items,
                                          selectedId: selectedId,
                                        );
                                        if (picked == null) {
                                          setSheetState(
                                            () => draft = draft.copyWith(
                                              clearTechnician: true,
                                            ),
                                          );
                                          return;
                                        }

                                        setSheetState(
                                          () => draft = draft.copyWith(
                                            technicianId: picked,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),
                              _sectionCard(
                                title: 'Rango de fechas',
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _choiceChips<OperationsDatePreset>(
                                      value: draft.datePreset,
                                      items: const [
                                        (OperationsDatePreset.today, 'Hoy'),
                                        (OperationsDatePreset.week, 'Semana'),
                                        (OperationsDatePreset.month, 'Mes'),
                                        (
                                          OperationsDatePreset.custom,
                                          'Personalizado',
                                        ),
                                      ],
                                      onChanged: (next) {
                                        setSheetState(() {
                                          draft = switch (next) {
                                            OperationsDatePreset.today =>
                                              draft.withTodayRange(),
                                            OperationsDatePreset.week =>
                                              draft.withWeekRange(),
                                            OperationsDatePreset.month =>
                                              draft.withMonthRange(),
                                            OperationsDatePreset.custom =>
                                              draft.copyWith(
                                                datePreset:
                                                    OperationsDatePreset.custom,
                                              ),
                                          };
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    Card(
                                      margin: EdgeInsets.zero,
                                      child: ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.date_range_outlined,
                                        ),
                                        title: const Text('Intervalo'),
                                        subtitle: Text(
                                          _rangeLabel(draft.range),
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right_rounded,
                                        ),
                                        onTap:
                                            draft.datePreset ==
                                                OperationsDatePreset.custom
                                            ? pickCustomRange
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _sectionCard(
                                title: 'Estado',
                                child: _choiceChips<OperationsStatusFilter>(
                                  value: draft.status,
                                  items: [
                                    (OperationsStatusFilter.all, 'Todos'),
                                    (
                                      OperationsStatusFilter.pending,
                                      'Pendientes',
                                    ),
                                    (
                                      OperationsStatusFilter.inProgress,
                                      'En proceso',
                                    ),
                                    (
                                      OperationsStatusFilter.completed,
                                      'Completadas',
                                    ),
                                    if (hasCancelled)
                                      (
                                        OperationsStatusFilter.cancelled,
                                        'Canceladas',
                                      ),
                                  ],
                                  onChanged: (next) => setSheetState(
                                    () => draft = draft.copyWith(status: next),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _sectionCard(
                                title: 'Prioridad',
                                child: _choiceChips<OperationsPriorityFilter>(
                                  value: draft.priority,
                                  items: [
                                    (OperationsPriorityFilter.all, 'Todas'),
                                    (OperationsPriorityFilter.high, 'Alta'),
                                    (OperationsPriorityFilter.normal, 'Normal'),
                                    if (hasLowPriority)
                                      (OperationsPriorityFilter.low, 'Baja'),
                                  ],
                                  onChanged: (next) => setSheetState(
                                    () =>
                                        draft = draft.copyWith(priority: next),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        footer(),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    final before = _filters;
    setState(() => _filters = result);

    // Optimiza el fetch remoto: solo cuando cambian rango o técnico.
    final beforeTech = (before.technicianId ?? '').trim();
    final nextTech = (result.technicianId ?? '').trim();
    final shouldFetchRemote =
        before.range != result.range || beforeTech != nextTech;

    if (shouldFetchRemote) {
      await widget.onApplyRemote(result.range, result.technicianId);
    }
  }

  // ignore: unused_element
  String _statusLabel(String raw) {
    switch (raw) {
      case 'reserved':
        return 'Pendiente';
      case 'survey':
        return 'Levantamiento';
      case 'scheduled':
        return 'Agendado';
      case 'in_progress':
        return 'En proceso';
      case 'warranty':
        return 'Garantía';
      case 'completed':
        return 'Completado';
      case 'closed':
        return 'Cerrado';
      default:
        return raw;
    }
  }

  String _typeLabel(String raw) {
    switch (raw) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Mantenimiento';
      case 'warranty':
        return 'Garantía';
      case 'pos_support':
        return 'Soporte POS';
      default:
        return raw;
    }
  }

  String _categoryLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cameras':
        return 'Cámaras';
      case 'gate_motor':
        return 'Motores de puertones';
      case 'alarm':
        return 'Alarma';
      case 'electric_fence':
        return 'Cerco eléctrico';
      case 'intercom':
        return 'Intercom';
      case 'pos':
        return 'Punto de ventas';
      default:
        return raw.trim().isEmpty ? 'General' : raw.trim();
    }
  }

  // ignore: unused_element
  String _techLabel(ServiceModel s) {
    if (s.assignments.isEmpty) return 'Sin asignar';
    final tech = s.assignments
        .where((a) => a.role == 'technician')
        .cast<ServiceAssignmentModel?>()
        .firstOrNull;
    return (tech ?? s.assignments.first).userName;
  }

  Future<void> _pickAndChangeOrderState(ServiceModel service) async {
    final current =
        ((service.adminStatus ?? '').trim().isNotEmpty
                ? service.adminStatus
                : (service.orderState.trim().isNotEmpty
                      ? service.orderState
                      : service.status))
            .toString()
            .trim()
            .toLowerCase();
    final picked = await StatusPickerSheet.show(context, current: current);
    if (!mounted || picked == null) return;

    final next = picked.trim().toLowerCase();
    if (next.isEmpty || next == current) return;

    try {
      await widget.onChangeOrderState(service.id, next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estado: ${StatusPickerSheet.label(next)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo cambiar el estado',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final range = _filters.range;
    final isDesktop =
        MediaQuery.sizeOf(context).width >=
        _OperacionesScreenState._desktopOperationsBreakpoint;

    String? effectiveAdminStatus(ServiceModel s) {
      final raw = (s.adminStatus ?? '').trim().toLowerCase();
      return raw.isEmpty ? null : raw;
    }

    ops.ServiceStatus effectiveLegacyStatus(ServiceModel s) {
      final raw = s.orderState.trim().isNotEmpty ? s.orderState : s.status;
      return ops.parseStatus(raw);
    }

    bool inRange(ServiceModel s) {
      final scheduled = s.scheduledStart;
      if (scheduled == null) return false;
      return !scheduled.isBefore(range.start) && !scheduled.isAfter(range.end);
    }

    final window = widget.state.services.where(inRange).toList()
      ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));

    bool isPendingByAdmin(String st) {
      switch (st) {
        case 'pendiente':
        case 'confirmada':
        case 'asignada':
        case 'reagendada':
          return true;
        default:
          return false;
      }
    }

    bool isInProgressByAdmin(String st) {
      switch (st) {
        case 'en_camino':
        case 'en_proceso':
          return true;
        default:
          return false;
      }
    }

    bool isCompletedByAdmin(String st) {
      switch (st) {
        case 'finalizada':
        case 'cerrada':
          return true;
        default:
          return false;
      }
    }

    bool isCancelledByAdmin(String st) => st == 'cancelada';

    bool isPendingByLegacy(ops.ServiceStatus st) {
      switch (st) {
        case ops.ServiceStatus.reserved:
        case ops.ServiceStatus.survey:
        case ops.ServiceStatus.scheduled:
        case ops.ServiceStatus.warranty:
          return true;
        default:
          return false;
      }
    }

    bool isInProgressByLegacy(ops.ServiceStatus st) =>
        st == ops.ServiceStatus.inProgress;

    bool isCompletedByLegacy(ops.ServiceStatus st) {
      switch (st) {
        case ops.ServiceStatus.completed:
        case ops.ServiceStatus.closed:
          return true;
        default:
          return false;
      }
    }

    final query = widget.searchCtrl.text.trim().toLowerCase();
    bool matchesQuery(ServiceModel s) {
      if (query.isEmpty) return true;
      final h = '${s.customerName} ${s.customerPhone} ${s.title}'.toLowerCase();
      return h.contains(query);
    }

    bool matchesStatus(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      final legacySt = effectiveLegacyStatus(s);
      switch (_filters.status) {
        case OperationsStatusFilter.all:
          return true;
        case OperationsStatusFilter.pending:
          return adminSt != null
              ? isPendingByAdmin(adminSt)
              : isPendingByLegacy(legacySt);
        case OperationsStatusFilter.inProgress:
          return adminSt != null
              ? isInProgressByAdmin(adminSt)
              : isInProgressByLegacy(legacySt);
        case OperationsStatusFilter.completed:
          return adminSt != null
              ? isCompletedByAdmin(adminSt)
              : isCompletedByLegacy(legacySt);
        case OperationsStatusFilter.cancelled:
          return adminSt != null
              ? isCancelledByAdmin(adminSt)
              : legacySt == ops.ServiceStatus.cancelled;
      }
    }

    bool matchesPriority(ServiceModel s) {
      switch (_filters.priority) {
        case OperationsPriorityFilter.all:
          return true;
        case OperationsPriorityFilter.high:
          return s.priority <= 1;
        case OperationsPriorityFilter.normal:
          return s.priority == 2;
        case OperationsPriorityFilter.low:
          return s.priority >= 3;
      }
    }

    bool matchesTechnician(ServiceModel s) {
      final techId = (_filters.technicianId ?? '').trim();
      if (techId.isEmpty) return true;
      if ((s.technicianId ?? '').trim() == techId) return true;
      return s.assignments.any((a) => a.userId == techId);
    }

    bool matchesCreator(ServiceModel s) {
      final createdBy = (_filters.createdByUserId ?? '').trim();
      if (createdBy.isEmpty) return true;
      return s.createdByUserId.trim() == createdBy;
    }

    // Orden requerido:
    // a) lista original (window ya está recortada por rango)
    // b) filtros
    // c) búsqueda
    final filteredOrders = window
        .where(
          (s) =>
              matchesStatus(s) &&
              matchesPriority(s) &&
              matchesTechnician(s) &&
              matchesCreator(s),
        )
        .toList(growable: false);

    final visibleOrders = filteredOrders
        .where(matchesQuery)
        .toList(growable: false);

    bool isPendingService(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      if (adminSt != null) return isPendingByAdmin(adminSt);
      return isPendingByLegacy(effectiveLegacyStatus(s));
    }

    bool isInProgressService(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      if (adminSt != null) return isInProgressByAdmin(adminSt);
      return isInProgressByLegacy(effectiveLegacyStatus(s));
    }

    bool isCompletedService(ServiceModel s) {
      final adminSt = effectiveAdminStatus(s);
      if (adminSt != null) return isCompletedByAdmin(adminSt);
      return isCompletedByLegacy(effectiveLegacyStatus(s));
    }

    int pendingCount(List<ServiceModel> list) =>
        list.where(isPendingService).length;
    int inProgressCount(List<ServiceModel> list) =>
        list.where(isInProgressService).length;
    int completedCount(List<ServiceModel> list) =>
        list.where(isCompletedService).length;

    final pendientesCount = pendingCount(visibleOrders);
    final procesoCount = inProgressCount(visibleOrders);
    final completadasCount = completedCount(visibleOrders);

    final atrasadas = visibleOrders.where((s) {
      if (isCompletedService(s)) return false;
      final due = s.scheduledStart;
      if (due == null) return false;
      return due.isBefore(now);
    }).length;

    assert(() {
      final rawStatuses = visibleOrders
          .map((s) => '${s.status}|${s.orderState}')
          .toSet()
          .toList(growable: false);
      debugPrint(
        '[operations] totalOrders=${widget.state.services.length} window=${window.length} filtered=${filteredOrders.length} visible=${visibleOrders.length} pend=$pendientesCount prog=$procesoCount comp=$completadasCount late=$atrasadas statuses=$rawStatuses',
      );
      return true;
    }());

    Widget summaryCard({
      required String label,
      required int value,
      required IconData icon,
      required Color tint,
      String? caption,
    }) {
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: tint, size: 17),
                    ),
                    const Spacer(),
                    Text(
                      '$value',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (isDesktop) {
      return _buildDesktopLayout(
        theme: theme,
        range: range,
        visibleOrders: visibleOrders,
        pendientesCount: pendientesCount,
        procesoCount: procesoCount,
        completadasCount: completadasCount,
        atrasadas: atrasadas,
      );
    }

    return _buildMobileLayout(
      theme: theme,
      range: range,
      visibleOrders: visibleOrders,
      pendientesCount: pendientesCount,
      procesoCount: procesoCount,
      completadasCount: completadasCount,
      atrasadas: atrasadas,
      summaryCard: summaryCard,
    );
  }

  Widget _buildMobileLayout({
    required ThemeData theme,
    required DateTimeRange range,
    required List<ServiceModel> visibleOrders,
    required int pendientesCount,
    required int procesoCount,
    required int completadasCount,
    required int atrasadas,
    required Widget Function({
      required String label,
      required int value,
      required IconData icon,
      required Color tint,
      String? caption,
    })
    summaryCard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.searchCtrl,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar servicios, clientes, técnicos…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Filtros',
              onPressed: _openFilters,
              icon: const Icon(Icons.filter_alt_rounded),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            summaryCard(
              label: 'Pendientes',
              value: pendientesCount,
              icon: Icons.error_outline,
              tint: theme.colorScheme.error,
              caption: atrasadas > 0 ? '$atrasadas atrasados' : null,
            ),
            const SizedBox(width: 6),
            summaryCard(
              label: 'En proceso',
              value: procesoCount,
              icon: Icons.play_circle_outline,
              tint: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 6),
            summaryCard(
              label: 'Completadas',
              value: completadasCount,
              icon: Icons.check_circle_outline,
              tint: theme.colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Agenda de Servicios · ${_rangeLabel(range)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: visibleOrders.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Sin servicios para mostrar.',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visibleOrders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildServiceAgendaTile(visibleOrders[index]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout({
    required ThemeData theme,
    required DateTimeRange range,
    required List<ServiceModel> visibleOrders,
    required int pendientesCount,
    required int procesoCount,
    required int completadasCount,
    required int atrasadas,
  }) {
    final pendingOrders = visibleOrders
        .where((service) {
          final raw = service.orderState.trim().isNotEmpty
              ? service.orderState
              : service.status;
          final status = ops.parseStatus(raw);
          return status == ops.ServiceStatus.reserved ||
              status == ops.ServiceStatus.survey ||
              status == ops.ServiceStatus.scheduled ||
              status == ops.ServiceStatus.warranty;
        })
        .toList(growable: false);

    final inProgressOrders = visibleOrders
        .where((service) {
          final raw = service.orderState.trim().isNotEmpty
              ? service.orderState
              : service.status;
          return ops.parseStatus(raw) == ops.ServiceStatus.inProgress;
        })
        .toList(growable: false);

    final completedOrders = visibleOrders
        .where((service) {
          final raw = service.orderState.trim().isNotEmpty
              ? service.orderState
              : service.status;
          final status = ops.parseStatus(raw);
          return status == ops.ServiceStatus.completed ||
              status == ops.ServiceStatus.closed;
        })
        .toList(growable: false);

    final hasQuery = widget.searchCtrl.text.trim().isNotEmpty;
    final hasExtraFilters =
        _filters.status != OperationsStatusFilter.all ||
        _filters.priority != OperationsPriorityFilter.all ||
        (_filters.technicianId ?? '').trim().isNotEmpty ||
        (_filters.createdByUserId ?? '').trim().isNotEmpty ||
        _filters.datePreset != OperationsDatePreset.today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.surfaceContainerLowest,
                theme.colorScheme.surface,
                theme.colorScheme.primary.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widget.searchCtrl,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText:
                              'Buscar servicios, clientes, técnicos o teléfonos…',
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: hasQuery
                              ? IconButton(
                                  tooltip: 'Limpiar búsqueda',
                                  onPressed: () {
                                    widget.searchCtrl.clear();
                                    _onQueryChange();
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: _openFilters,
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Filtros'),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Actualizar tablero',
                      onPressed: widget.onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _OperationsDesktopMetricCard(
                        label: 'Pendientes',
                        value: pendientesCount,
                        icon: Icons.error_outline,
                        tint: theme.colorScheme.error,
                        caption: atrasadas > 0
                            ? '$atrasadas atrasadas'
                            : 'Sin atraso',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OperationsDesktopMetricCard(
                        label: 'En proceso',
                        value: procesoCount,
                        icon: Icons.play_circle_outline,
                        tint: theme.colorScheme.tertiary,
                        caption: 'Atención activa',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OperationsDesktopMetricCard(
                        label: 'Completadas',
                        value: completadasCount,
                        icon: Icons.check_circle_outline,
                        tint: theme.colorScheme.primary,
                        caption: 'Servicios cerrados',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _OperationsDesktopMetricCard(
                        label: 'Visibles',
                        value: visibleOrders.length,
                        icon: Icons.dashboard_customize_outlined,
                        tint: theme.colorScheme.secondary,
                        caption: _rangeLabel(range),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 320,
                child: ListView(
                  children: [
                    InfoCard(
                      title: 'Control operativo',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _OperationsDesktopInfoRow(
                            label: 'Rango activo',
                            value: _rangeLabel(range),
                          ),
                          const SizedBox(height: 10),
                          _OperationsDesktopInfoRow(
                            label: 'Servicios visibles',
                            value: '${visibleOrders.length}',
                          ),
                          const SizedBox(height: 10),
                          _OperationsDesktopInfoRow(
                            label: 'Pendientes tardíos',
                            value: '$atrasadas',
                            emphasize: atrasadas > 0,
                          ),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _openFilters,
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Abrir filtros'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (hasQuery || hasExtraFilters)
                      InfoCard(
                        title: 'Contexto activo',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _OperationsDesktopBadge(label: _rangeLabel(range)),
                            if (hasQuery)
                              _OperationsDesktopBadge(
                                label:
                                    'Busqueda: ${widget.searchCtrl.text.trim()}',
                              ),
                            if (_filters.status != OperationsStatusFilter.all)
                              _OperationsDesktopBadge(
                                label:
                                    'Estado: ${_statusFilterLabel(_filters.status)}',
                              ),
                            if (_filters.priority !=
                                OperationsPriorityFilter.all)
                              _OperationsDesktopBadge(
                                label:
                                    'Prioridad: ${_priorityFilterLabel(_filters.priority)}',
                              ),
                            if ((_filters.technicianId ?? '').trim().isNotEmpty)
                              const _OperationsDesktopBadge(
                                label: 'Tecnico filtrado',
                              ),
                            if ((_filters.createdByUserId ?? '')
                                .trim()
                                .isNotEmpty)
                              const _OperationsDesktopBadge(
                                label: 'Usuario filtrado',
                              ),
                          ],
                        ),
                      ),
                    if (hasQuery || hasExtraFilters) const SizedBox(height: 12),
                    InfoCard(
                      title: 'Lectura rapida',
                      child: Column(
                        children: [
                          _OperationsDesktopLegendRow(
                            icon: Icons.error_outline,
                            label: 'Pendientes por confirmar o ejecutar',
                            tint: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 10),
                          _OperationsDesktopLegendRow(
                            icon: Icons.play_circle_outline,
                            label: 'Servicios tecnicos activos',
                            tint: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(height: 10),
                          _OperationsDesktopLegendRow(
                            icon: Icons.check_circle_outline,
                            label: 'Completados o cerrados',
                            tint: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _OperationsDesktopColumn(
                        title: 'Pendientes',
                        count: pendingOrders.length,
                        tint: theme.colorScheme.error,
                        emptyLabel: 'No hay servicios pendientes.',
                        children: [
                          for (final service in pendingOrders)
                            _buildServiceAgendaTile(service),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _OperationsDesktopColumn(
                        title: 'En proceso',
                        count: inProgressOrders.length,
                        tint: theme.colorScheme.tertiary,
                        emptyLabel: 'No hay servicios en proceso.',
                        children: [
                          for (final service in inProgressOrders)
                            _buildServiceAgendaTile(service),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _OperationsDesktopColumn(
                        title: 'Completadas',
                        count: completedOrders.length,
                        tint: theme.colorScheme.primary,
                        emptyLabel: 'No hay servicios completados.',
                        children: [
                          for (final service in completedOrders)
                            _buildServiceAgendaTile(service),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _statusFilterLabel(OperationsStatusFilter value) {
    switch (value) {
      case OperationsStatusFilter.all:
        return 'Todos';
      case OperationsStatusFilter.pending:
        return 'Pendientes';
      case OperationsStatusFilter.inProgress:
        return 'En proceso';
      case OperationsStatusFilter.completed:
        return 'Completadas';
      case OperationsStatusFilter.cancelled:
        return 'Canceladas';
    }
  }

  String _priorityFilterLabel(OperationsPriorityFilter value) {
    switch (value) {
      case OperationsPriorityFilter.all:
        return 'Todas';
      case OperationsPriorityFilter.high:
        return 'Alta';
      case OperationsPriorityFilter.normal:
        return 'Normal';
      case OperationsPriorityFilter.low:
        return 'Baja';
    }
  }

  Widget _buildServiceAgendaTile(ServiceModel s) {
    final type = _typeLabel(s.serviceType);
    final category = _categoryLabel(s.category);
    final subtitle = category.isEmpty ? type : '$type · $category';
    final tech = _techLabel(s);

    final scheduled = s.scheduledStart;
    final scheduledText = scheduled == null
        ? null
        : DateFormat('EEE dd/MM HH:mm', 'es').format(scheduled);

    final perms = OperationsPermissions(user: widget.currentUser, service: s);
    final canChangePhase = perms.canChangePhase;

    return ServiceAgendaCard(
      service: s,
      subtitle: subtitle,
      technicianText: tech,
      scheduledText: scheduledText,
      onView: () => widget.onOpenService(s),
      onChangeState: () => _pickAndChangeOrderState(s),
      onChangePhase: !canChangePhase
          ? null
          : () {
              unawaited(() async {
                final draft = await ServiceActionsSheet.pickChangePhaseDraft(
                  context,
                  current: s.currentPhase,
                  initialScheduledAt: s.scheduledStart,
                );
                if (!mounted || draft == null) return;

                final next = (draft['phase'] ?? '').trim();
                final scheduledAtRaw = (draft['scheduledAt'] ?? '').trim();
                if (next.isEmpty) return;

                final scheduledAt = DateTime.tryParse(scheduledAtRaw);
                if (scheduledAt == null) return;

                try {
                  await widget.onChangePhase(
                    s,
                    next,
                    scheduledAt,
                    draft['note'],
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fase: ${phaseLabel(next)}')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e is ApiException ? e.message : '$e'),
                    ),
                  );
                }
              }());
            },
    );
  }
}

class _OperationsDesktopMetricCard extends StatelessWidget {
  const _OperationsDesktopMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.caption,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color tint;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$value',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationsDesktopColumn extends StatelessWidget {
  const _OperationsDesktopColumn({
    required this.title,
    required this.count,
    required this.tint,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final int count;
  final Color tint;
  final String emptyLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(color: tint.withValues(alpha: 0.18)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: children.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        emptyLabel,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: children.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => children[index],
                  ),
          ),
        ],
      ),
    );
  }
}

class _OperationsDesktopInfoRow extends StatelessWidget {
  const _OperationsDesktopInfoRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: emphasize ? theme.colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

class _OperationsDesktopLegendRow extends StatelessWidget {
  const _OperationsDesktopLegendRow({
    required this.icon,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: tint, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _OperationsDesktopBadge extends StatelessWidget {
  const _OperationsDesktopBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ReservaScreen extends StatelessWidget {
  final Future<void> Function(_CreateServiceDraft draft) onCreate;

  const _ReservaScreen({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva reserva')),
      body: _CreateReservationTab(onCreate: onCreate),
    );
  }
}

class _ServiceDetailPanel extends ConsumerStatefulWidget {
  final ServiceModel service;
  final Future<void> Function(String status) onChangeStatus;
  final Future<void> Function(String orderState) onChangeOrderState;
  final Future<void> Function(String adminPhase) onChangeAdminPhase;
  final Future<void> Function(DateTime start, DateTime end) onSchedule;
  final Future<void> Function() onCreateWarranty;
  final Future<void> Function(List<Map<String, String>> assignments) onAssign;
  final Future<void> Function(String stepId, bool done) onToggleStep;
  final Future<void> Function(String message) onAddNote;
  final Future<void> Function() onUploadEvidence;

  const _ServiceDetailPanel({
    required this.service,
    required this.onChangeStatus,
    required this.onChangeOrderState,
    required this.onChangeAdminPhase,
    required this.onSchedule,
    required this.onCreateWarranty,
    required this.onAssign,
    required this.onToggleStep,
    required this.onAddNote,
    required this.onUploadEvidence,
  });

  @override
  ConsumerState<_ServiceDetailPanel> createState() =>
      _ServiceDetailPanelState();
}

class _ServiceDetailPanelState extends ConsumerState<_ServiceDetailPanel> {
  final _noteCtrl = TextEditingController();

  late ServiceModel _service;

  List<ServicePhaseHistoryModel> _phaseHistory = const [];
  bool _phaseHistoryLoading = false;
  String? _phaseHistoryError;

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _loadPhaseHistory();
  }

  @override
  void didUpdateWidget(covariant _ServiceDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service.id != widget.service.id) {
      _service = widget.service;
      _phaseHistory = const [];
      _phaseHistoryError = null;
      _phaseHistoryLoading = false;
      _loadPhaseHistory();
    }
  }

  Future<void> _loadPhaseHistory() async {
    final serviceId = _service.id.trim();
    if (serviceId.isEmpty) return;

    setState(() {
      _phaseHistoryLoading = true;
      _phaseHistoryError = null;
    });

    try {
      final items = await ref
          .read(operationsRepositoryProvider)
          .listServicePhases(serviceId);
      if (!mounted) return;
      setState(() {
        _phaseHistory = items;
        _phaseHistoryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phaseHistoryLoading = false;
        _phaseHistoryError = e is ApiException
            ? e.message
            : 'No se pudo cargar historial de fases';
      });
    }
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'reserved':
        return 'Reserva';
      case 'survey':
        return 'Levantamiento';
      case 'scheduled':
        return 'Servicio (agendado)';
      case 'in_progress':
        return 'Servicio (en proceso)';
      case 'warranty':
        return 'Garantía';
      case 'completed':
        return 'Finalizado';
      case 'closed':
        return 'Cerrado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return raw;
    }
  }

  String _serviceTypeLabel(String raw) {
    switch (raw) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Servicio técnico';
      case 'warranty':
        return 'Garantía';
      default:
        return raw;
    }
  }

  String _categoryLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cameras':
        return 'Cámaras';
      case 'gate_motor':
        return 'Motores de puertones';
      case 'alarm':
        return 'Alarma';
      case 'electric_fence':
        return 'Cerco eléctrico';
      case 'intercom':
        return 'Intercom';
      case 'pos':
        return 'Punto de ventas';
      default:
        return raw.trim().isEmpty ? 'General' : raw.trim();
    }
  }

  String _orderStateLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pendiente':
      case 'pending':
        return 'Pendiente';
      case 'confirmada':
      case 'confirmed':
        return 'Confirmada';
      case 'asignada':
      case 'assigned':
        return 'Asignada';
      case 'en_proceso':
      case 'in_progress':
        return 'En progreso';
      case 'finalizada':
      case 'finalized':
        return 'Finalizada';
      case 'cancelada':
      case 'cancelled':
        return 'Cancelada';
      case 'reagendada':
      case 'rescheduled':
        return 'Reagendada';
      case 'cerrada':
        return 'Cerrada';
      default:
        return raw;
    }
  }

  String _orderTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'reserva':
        return 'Reserva';
      case 'instalacion':
        return 'Instalación';
      case 'mantenimiento':
      case 'servicio':
        return 'Mantenimiento';
      case 'garantia':
        return 'Garantía';
      case 'levantamiento':
        return 'Levantamiento';
      default:
        return raw;
    }
  }

  String _effectiveAdminPhase(ServiceModel s) {
    final raw = (s.adminPhase ?? '').trim().toLowerCase();
    if (raw.isNotEmpty) return raw;
    final type = s.orderType.trim().toLowerCase();
    return type == 'reserva' ? 'reserva' : 'programacion';
  }

  String _effectiveAdminStatus(ServiceModel s) {
    final raw = (s.adminStatus ?? '').trim().toLowerCase();
    if (raw.isNotEmpty) return raw;
    final fallback = s.orderState.trim().isNotEmpty ? s.orderState : s.status;
    return fallback.trim().toLowerCase();
  }

  Future<void> _pickAndChangeAdminStatus(ServiceModel service) async {
    final current = _effectiveAdminStatus(service);
    final picked = await StatusPickerSheet.show(context, current: current);
    if (!mounted || picked == null) return;
    final next = picked.trim().toLowerCase();
    if (next.isEmpty || next == current) return;

    try {
      await widget.onChangeOrderState(next);
      if (!mounted) return;
      setState(() => _service = _service.copyWith(adminStatus: next));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estado: ${StatusPickerSheet.label(next)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _pickAndChangeAdminPhase(ServiceModel service) async {
    final current = _effectiveAdminPhase(service);
    final allowed = ServiceActionsSheet.allowedNextAdminPhases(current);
    if (allowed.isEmpty) return;

    final picked = await ServiceActionsSheet.pickAdminPhase(
      context,
      current: current,
      allowed: allowed,
    );
    if (!mounted || picked == null) return;
    final next = picked.trim().toLowerCase();
    if (next.isEmpty || next == current) return;

    try {
      await widget.onChangeAdminPhase(next);
      if (!mounted) return;
      setState(() => _service = _service.copyWith(adminPhase: next));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fase: ${adminPhaseLabel(next)}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  String? _suggestOrderStateForStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'scheduled':
        return 'confirmada';
      case 'in_progress':
        return 'en_proceso';
      case 'completed':
      case 'closed':
        return 'finalizada';
      case 'cancelled':
        return 'cancelada';
      default:
        return null;
    }
  }

  Future<void> _setStatusWithConfirm(
    String targetStatus, {
    bool closePanel = true,
  }) async {
    final service = _service;
    if (targetStatus == service.status) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar cambio'),
          content: Text(
            'Vas a cambiar la etapa de "${_statusLabel(service.status)}" a "${_statusLabel(targetStatus)}".\n\n¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (!mounted || ok != true) return;

    await widget.onChangeStatus(targetStatus);
    if (!mounted) return;

    setState(() {
      _service = _service.copyWith(status: targetStatus);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Etapa: ${_statusLabel(targetStatus)}')),
    );

    if (closePanel) {
      // Mantiene el comportamiento anterior cuando se cambia desde Acciones.
      Navigator.pop(context);
    }
  }

  Future<void> _pickStageFlow({
    required bool canOperate,
    required List<String> allowedTargets,
  }) async {
    final service = _service;

    if (!canOperate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No autorizado')));
      return;
    }

    if (allowedTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay etapas disponibles')),
      );
      return;
    }

    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: allowedTargets
                .map(
                  (s) => ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(_statusLabel(s))),
                        if (s == service.status)
                          const Icon(Icons.check_rounded, size: 18),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, s),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );

    if (!mounted || picked == null) return;
    final target = picked.trim().toLowerCase();
    if (target.isEmpty || target == service.status.trim().toLowerCase()) return;

    await _setStatusWithConfirm(target, closePanel: false);

    final suggestion = _suggestOrderStateForStatus(target);
    final currentAdminStatus =
        ((service.adminStatus ?? '').trim().isNotEmpty
                ? service.adminStatus
                : (service.orderState.trim().isNotEmpty
                      ? service.orderState
                      : service.status))
            .toString()
            .trim()
            .toLowerCase();
    if (!mounted || suggestion == null || suggestion == currentAdminStatus) {
      return;
    }

    final applySuggested = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sugerencia'),
          content: Text(
            'Esta etapa normalmente usa el estado de orden "${_orderStateLabel(suggestion)}". ¿Deseas aplicarlo también?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );

    if (!mounted || applySuggested != true) return;

    await widget.onChangeOrderState(suggestion);
    if (!mounted) return;

    setState(() {
      _service = _service.copyWith(adminStatus: suggestion);
    });
  }

  Future<void> _pickScheduleFlow(ServiceModel service) async {
    final now = DateTime.now();
    final startInitial = service.scheduledStart ?? now;
    final start = await _pickDateTime(
      helpText: 'Selecciona inicio',
      initial: startInitial,
    );
    if (!mounted) return;
    if (start == null) return;

    final endInitial =
        service.scheduledEnd ?? start.add(const Duration(hours: 2));
    final end = await _pickDateTime(
      helpText: 'Selecciona fin',
      initial: endInitial,
    );
    if (!mounted) return;
    if (end == null) return;

    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El fin debe ser posterior al inicio')),
      );
      return;
    }

    await widget.onSchedule(start, end);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Agenda actualizada')));

    Navigator.pop(context);
  }

  Future<void> _assignTechsFlow() async {
    final ids = await _askTechIds(context);
    if (ids == null || ids.isEmpty) return;
    await widget.onAssign(
      ids
          .map((id) => <String, String>{'userId': id, 'role': 'assistant'})
          .toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Técnicos asignados')));
  }

  Future<DateTime?> _pickDateTime({
    required String helpText,
    required DateTime initial,
  }) async {
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      initialDate: DateTime(initial.year, initial.month, initial.day),
      helpText: helpText,
    );
    if (!mounted || pickedDate == null) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _deleteWithConfirm(ServiceModel service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar servicio'),
          content: Text(
            'Vas a eliminar "${service.title.trim().isEmpty ? 'Servicio' : service.title.trim()}".\n\nEsta acción no se puede deshacer. ¿Seguro que deseas hacerlo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (!mounted || ok != true) return;

    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .deleteService(service.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Servicio eliminado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    final auth = ref.watch(authStateProvider);
    final user = auth.user;

    final perms = OperationsPermissions(user: user, service: service);
    final canOperate = perms.canOperate;
    final canDelete = perms.canDelete;
    final canEdit = perms.canCritical;
    final allowedStatusTargets = perms.allowedNextStatuses();

    final typeText = _serviceTypeLabel(service.serviceType);
    final categoryText = _categoryLabel(service.category);
    final descText = service.description.trim();
    final customerName = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();
    final customerPhone = service.customerPhone.trim();
    final addressText = service.customerAddress.trim();

    final techNames = service.assignments
        .map((a) => a.userName.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final tags = service.tags
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    String money(double? v) {
      if (v == null) return '—';
      final safe = v.isNaN ? 0.0 : v;
      return 'RD\$${safe.toStringAsFixed(2)}';
    }

    final headerTitle = categoryText.isEmpty
        ? typeText
        : '$typeText · $categoryText';
    final headerSubtitle = customerPhone.isEmpty
        ? customerName
        : '$customerName · $customerPhone';

    final statusChipValue = service.orderState.trim().isNotEmpty
        ? service.orderState.trim()
        : service.status.trim();

    final adminStatusValue = _effectiveAdminStatus(service);
    final statusChipEffective = (service.adminStatus ?? '').trim().isNotEmpty
        ? adminStatusValue
        : statusChipValue;

    final location = buildServiceLocationInfo(addressOrText: addressText);

    Future<void> editFlow() async {
      final messenger = ScaffoldMessenger.of(context);

      if (!canEdit) {
        final reason = perms.criticalDeniedReason ?? 'No autorizado';
        messenger.showSnackBar(SnackBar(content: Text(reason)));
        return;
      }

      String? addressLine;
      String? gpsLine;
      String? mapsLine;
      for (final line in addressText.split('\n')) {
        final v = line.trim();
        if (v.isEmpty) continue;
        final lower = v.toLowerCase();
        if (lower.startsWith('gps:')) {
          gpsLine = v.substring(4).trim();
          continue;
        }
        if (lower.startsWith('maps:')) {
          mapsLine = v.substring(5).trim();
          continue;
        }
        addressLine ??= v;
      }

      final descCtrl = TextEditingController(
        text: service.description.trim().isEmpty ? '' : service.description,
      );
      final addrCtrl = TextEditingController(text: addressLine ?? '');
      final gpsCtrl = TextEditingController(text: gpsLine ?? mapsLine ?? '');

      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Editar orden'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Nota / descripción',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addrCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Dirección',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: gpsCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Ubicación (lat,lng o link de Maps)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        descCtrl.dispose();
        addrCtrl.dispose();
        gpsCtrl.dispose();
        return;
      }

      if (ok != true) {
        descCtrl.dispose();
        addrCtrl.dispose();
        gpsCtrl.dispose();
        return;
      }

      String? buildAddressSnapshot(String address, String gpsText) {
        final a = address.trim();
        final g = gpsText.trim();
        if (a.isEmpty && g.isEmpty) return null;

        final point = parseLatLngFromText(g);
        if (point != null) {
          final lines = <String>[];
          if (a.isNotEmpty) lines.add(a);
          lines.add('GPS: ${formatLatLng(point)}');
          lines.add('MAPS: ${buildGoogleMapsSearchUrl(point)}');
          return lines.join('\n');
        }

        final isUrl = RegExp(r'https?://', caseSensitive: false).hasMatch(g);
        final lines = <String>[];
        if (a.isNotEmpty) lines.add(a);
        if (g.isNotEmpty) {
          lines.add(isUrl ? 'MAPS: $g' : 'GPS: $g');
        }
        return lines.join('\n');
      }

      final newDesc = descCtrl.text.trim();
      final snapshot = buildAddressSnapshot(addrCtrl.text, gpsCtrl.text);

      descCtrl.dispose();
      addrCtrl.dispose();
      gpsCtrl.dispose();

      try {
        final updated = await ref
            .read(operationsControllerProvider.notifier)
            .updateService(
              serviceId: service.id,
              description: newDesc.isEmpty ? 'Sin nota' : newDesc,
              addressSnapshot: snapshot,
            );
        if (!mounted) return;
        setState(() => _service = updated);
        messenger.showSnackBar(
          const SnackBar(content: Text('Orden actualizada')),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : '$e')),
        );
      }
    }

    Future<void> openActions() async {
      final messenger = ScaffoldMessenger.of(context);

      await ServiceActionsSheet.show(
        context,
        service: service,
        canOperate: canOperate,
        operateDeniedReason: perms.operateDeniedReason,
        canEdit: canEdit,
        editDeniedReason: perms.criticalDeniedReason,
        canChangePhase: perms.canChangePhase,
        changePhaseDeniedReason: perms.changePhaseDeniedReason,
        onChangePhase: (phase, scheduledAt, note) async {
          final missing = _missingPhaseRequirements(service, phase);
          if (missing.isNotEmpty) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'No se puede cambiar a ${phaseLabel(phase)}. Falta: ${missing.join(', ')}',
                ),
              ),
            );
            return;
          }
          try {
            final updated = await ref
                .read(operationsControllerProvider.notifier)
                .changePhaseOptimistic(
                  service.id,
                  phase,
                  scheduledAt: scheduledAt,
                  note: note,
                );

            if (!mounted) return;
            setState(() => _service = updated);
            await _loadPhaseHistory();
            if (!mounted) return;

            messenger.showSnackBar(
              SnackBar(
                content: Text('Fase: ${phaseLabel(updated.currentPhase)}'),
              ),
            );

            final nextPhase = updated.currentPhase.trim().toLowerCase();
            final currentOrderState = updated.orderState.trim().toLowerCase();
            if (nextPhase == 'instalacion' && currentOrderState == 'pending') {
              if (!context.mounted) return;
              final applySuggested = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Sugerencia'),
                    content: const Text(
                      'Esta fase normalmente usa el estado de orden "En progreso". ¿Deseas aplicarlo también?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('No'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  );
                },
              );

              if (!mounted || applySuggested != true) return;
              await widget.onChangeOrderState('in_progress');
              if (!mounted) return;
              setState(() {
                _service = _service.copyWith(orderState: 'in_progress');
              });
            }
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e is ApiException ? e.message : '$e')),
            );
          }
        },
        allowedStatusTargets: allowedStatusTargets,
        canDelete: canDelete,
        deleteDeniedReason: perms.criticalDeniedReason,
        onEdit: editFlow,
        onChangeStatus: (status) => _setStatusWithConfirm(status),
        onPickSchedule: () => _pickScheduleFlow(service),
        onAssignTechs: _assignTechsFlow,
        onUploadEvidence: widget.onUploadEvidence,
        onCreateWarranty: widget.onCreateWarranty,
        onDelete: () => _deleteWithConfirm(service),
        onAddNote: (message) async {
          await widget.onAddNote(message);
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Marcado en historial')),
          );
        },
        onMarkPendingBy: (reason) async {
          await widget.onAddNote('Pendiente por: $reason');
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text('Marcado como pendiente')),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ServiceHeader(
          title: headerTitle,
          subtitle: headerSubtitle,
          status: statusChipEffective,
          onActions: openActions,
        ),
        if (descText.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            descText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 12),
        InfoCard(
          title: 'Resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Fase de orden', _orderTypeLabel(service.orderType)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        'Estado (admin)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        StatusPickerSheet.label(adminStatusValue),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: canOperate
                          ? () => _pickAndChangeAdminStatus(service)
                          : null,
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        'Fase (admin)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        adminPhaseLabel(_effectiveAdminPhase(service)),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed:
                          canOperate &&
                              ServiceActionsSheet.allowedNextAdminPhases(
                                _effectiveAdminPhase(service),
                              ).isNotEmpty
                          ? () => _pickAndChangeAdminPhase(service)
                          : null,
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
              ),

              _kv(context, 'Prioridad', 'P${service.priority}'),
              _kv(context, 'Fase técnica', phaseLabel(service.currentPhase)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        'Estado técnico',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusLabel(service.status),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: canOperate
                          ? () => _pickStageFlow(
                              canOperate: canOperate,
                              allowedTargets: allowedStatusTargets,
                            )
                          : null,
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
              ),
              _kv(
                context,
                'Creado por',
                service.createdByName.trim().isEmpty
                    ? '—'
                    : service.createdByName.trim(),
              ),
              _kv(
                context,
                'Estado (legacy)',
                service.orderState.trim().isEmpty
                    ? '—'
                    : _orderStateLabel(service.orderState),
              ),
              if (service.scheduledStart != null)
                _kv(
                  context,
                  'Inicio',
                  dateFormat.format(service.scheduledStart!),
                ),
              if (service.scheduledEnd != null)
                _kv(context, 'Fin', dateFormat.format(service.scheduledEnd!)),
              if (service.completedAt != null)
                _kv(
                  context,
                  'Completado',
                  dateFormat.format(service.completedAt!),
                ),
              _kv(
                context,
                'Técnicos',
                techNames.isEmpty ? 'Sin asignar' : techNames.join(', '),
              ),
              if (service.isSeguro) _kv(context, 'Seguro', 'Sí'),
              if (tags.isNotEmpty) _kv(context, 'Tags', tags.join(', ')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Ubicación',
          trailing: IconButton(
            tooltip: 'Abrir Maps',
            onPressed: location.canOpenMaps
                ? () async {
                    final uri = location.mapsUri;
                    if (uri == null) return;
                    await safeOpenUrl(
                      context,
                      uri,
                      copiedMessage: 'Link copiado',
                    );
                  }
                : null,
            icon: const Icon(Icons.map_outlined),
          ),
          child: Text(
            location.label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Finanzas',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Cotizado', money(service.quotedAmount)),
              _kv(context, 'Abono', money(service.depositAmount)),
              _kv(
                context,
                'Total',
                money(service.quotedAmount ?? service.depositAmount),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Gestión de facturación del servicio',
          child: Builder(
            builder: (context) {
              final c = service.closing;

              String invoiceStatus() {
                if (c == null) return 'No generada';
                if ((c.invoiceFinalFileId ?? '').isNotEmpty) return 'Final';
                if ((c.invoiceApprovedFileId ?? '').isNotEmpty) {
                  return 'Aprobada';
                }
                if ((c.invoiceDraftFileId ?? '').isNotEmpty) {
                  return 'Pendiente aprobación';
                }
                return 'En proceso';
              }

              String warrantyStatus() {
                if (c == null) return 'No generada';
                if ((c.warrantyFinalFileId ?? '').isNotEmpty) return 'Final';
                if ((c.warrantyApprovedFileId ?? '').isNotEmpty) {
                  return 'Aprobada';
                }
                if ((c.warrantyDraftFileId ?? '').isNotEmpty) {
                  return 'Pendiente aprobación';
                }
                return 'En proceso';
              }

              String approvalStatus() {
                final s = c?.approvalStatus.toUpperCase().trim() ?? '';
                if (s == 'APPROVED') return 'Aprobada';
                if (s == 'REJECTED') return 'Rechazada';
                if (s == 'PENDING') return 'Pendiente';
                return s.isEmpty ? 'N/D' : s;
              }

              String signatureStatus() {
                final s = c?.signatureStatus.toUpperCase().trim() ?? '';
                if (s == 'SIGNED') return 'Firmada';
                if (s == 'SKIPPED') return 'No firmada (opcional)';
                if (s == 'PENDING') return 'Pendiente';
                return s.isEmpty ? 'N/D' : s;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv(context, 'Factura', invoiceStatus()),
                  _kv(context, 'Garantía', warrantyStatus()),
                  _kv(context, 'Aprobación', approvalStatus()),
                  _kv(context, 'Firma cliente', signatureStatus()),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Checklist',
          child: service.steps.isEmpty
              ? const Text('Sin checklist')
              : Column(
                  children: [
                    for (final step in service.steps)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(step.stepLabel),
                        subtitle: step.doneAt == null
                            ? null
                            : Text(
                                'Completado ${dateFormat.format(step.doneAt!)}',
                              ),
                        value: step.isDone,
                        onChanged: (value) {
                          if (!canOperate) return;
                          if (value == null) return;
                          widget.onToggleStep(step.id, value);
                        },
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Evidencias',
          child: service.files.isEmpty
              ? const Text('Sin evidencias todavía')
              : Column(
                  children: [
                    for (final file in service.files)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(file.fileType),
                        subtitle: Text(file.fileUrl),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Historial',
          child: service.updates.isEmpty
              ? const Text('Sin movimientos')
              : Column(
                  children: [
                    for (final update in service.updates.take(10))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(
                          update.message.isEmpty ? update.type : update.message,
                        ),
                        subtitle: Text(
                          '${update.changedBy} · ${update.createdAt == null ? '-' : dateFormat.format(update.createdAt!)}',
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Historial de fases',
          child: _phaseHistoryLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                )
              : (_phaseHistoryError != null)
              ? Text(_phaseHistoryError!)
              : _phaseHistory.isEmpty
              ? const Text('Sin movimientos de fase')
              : Column(
                  children: [
                    for (final item in _phaseHistory.take(10))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(phaseLabel(item.phase)),
                        subtitle: Text(
                          '${item.changedBy} · ${item.changedAt == null ? '-' : dateFormat.format(item.changedAt!)}${(item.note ?? '').trim().isEmpty ? '' : '\n${item.note!.trim()}'}',
                        ),
                        isThreeLine: (item.note ?? '').trim().isNotEmpty,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        InfoCard(
          title: 'Notas internas',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Escribe una nota interna…',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () {
                    final note = _noteCtrl.text.trim();
                    if (note.isEmpty) return;
                    widget.onAddNote(note);
                    _noteCtrl.clear();
                  },
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Guardar nota'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<List<String>?> _askTechIds(BuildContext context) async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Asignar técnicos'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'UUID1, UUID2, UUID3',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      );
      if (ok != true) return null;

      final value = ctrl.text.trim();
      if (value.isEmpty) return null;
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    } finally {
      ctrl.dispose();
    }
  }

  // ignore: unused_element
  Future<String?> _askReason(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motivo pendiente'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    return ok == true ? text : null;
  }

  // ignore: unused_element
  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

Widget _kv(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class OperacionesHistorialBody extends ConsumerStatefulWidget {
  const OperacionesHistorialBody({super.key});

  @override
  ConsumerState<OperacionesHistorialBody> createState() =>
      OperacionesHistorialBodyState();
}

class OperacionesHistorialBodyState
    extends ConsumerState<OperacionesHistorialBody> {
  bool _loading = false;
  String? _error;
  List<ServiceModel> _items = const [];
  String _query = '';

  static const int _pageSize = 120;
  static const int _maxPages = 25;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(operationsRepositoryProvider);

      Future<List<ServiceModel>> listAllByStatus(String status) async {
        final all = <ServiceModel>[];
        for (var page = 1; page <= _maxPages; page++) {
          final res = await repo.listServices(
            status: status,
            page: page,
            pageSize: _pageSize,
          );
          all.addAll(res.items);
          if (res.items.length < _pageSize) break;
        }
        return all;
      }

      final results = await Future.wait([
        listAllByStatus('completed'),
        listAllByStatus('closed'),
      ]);

      final completed = results[0];
      final closed = results[1];

      final byId = <String, ServiceModel>{
        for (final item in completed) item.id: item,
        for (final item in closed) item.id: item,
      };

      DateTime? lastUpdateAt(ServiceModel s) {
        final dates = s.updates
            .map((u) => u.createdAt)
            .whereType<DateTime>()
            .toList();
        if (dates.isEmpty) return null;
        dates.sort();
        return dates.last;
      }

      final merged = byId.values.toList()
        ..sort((a, b) {
          final ad = lastUpdateAt(a) ?? a.completedAt;
          final bd = lastUpdateAt(b) ?? b.completedAt;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });

      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'No se pudo cargar historial';
      });
    }
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'completed':
        return 'Finalizada';
      case 'closed':
        return 'Cerrada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return raw;
    }
  }

  String _typeLabel(String raw) {
    switch (raw) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Servicio técnico';
      case 'warranty':
        return 'Garantía';
      case 'pos_support':
        return 'Soporte POS';
      case 'other':
        return 'Otro';
      default:
        return raw;
    }
  }

  IconData _typeIcon(String raw) {
    switch (raw) {
      case 'installation':
        return Icons.handyman_outlined;
      case 'maintenance':
        return Icons.build_circle_outlined;
      case 'warranty':
        return Icons.verified_outlined;
      case 'pos_support':
        return Icons.point_of_sale_outlined;
      default:
        return Icons.work_outline;
    }
  }

  DateTime? _lastUpdateAt(ServiceModel s) {
    final dates = s.updates
        .map((u) => u.createdAt)
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.last;
  }

  Future<void> _openDetail(ServiceModel service) async {
    final theme = Theme.of(context);
    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');
    final updates = [...service.updates]
      ..sort((a, b) {
        final ad = a.createdAt;
        final bd = b.createdAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.85,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    service.customerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${service.customerPhone} · ${service.customerAddress}'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(context, 'Estado', _statusLabel(service.status)),
                      _pill(context, 'Tipo', _typeLabel(service.serviceType)),
                      _pill(context, 'Prioridad', 'P${service.priority}'),
                      if (service.isSeguro) _pill(context, 'SEGURO', 'Sí'),
                      _pill(context, 'Último', () {
                        final last =
                            _lastUpdateAt(service) ?? service.completedAt;
                        return last == null ? '—' : df.format(last);
                      }()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    service.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Historial de proceso',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: updates.isEmpty
                        ? Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Sin actualizaciones registradas para este servicio.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: updates.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final u = updates[index];
                              final stamp = u.createdAt == null
                                  ? '—'
                                  : df.format(u.createdAt!);
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        u.message,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text('$stamp · ${u.changedBy}'),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pill(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Text('$label: $value'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _items
        : _items.where((s) {
            final haystack = '${s.customerName} ${s.customerPhone} ${s.title}'
                .toLowerCase();
            return haystack.contains(query);
          }).toList();

    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Historial por cliente',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar cliente o teléfono',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (_error != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!_loading && _error == null && filtered.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Sin historial para mostrar.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filtered.map((service) {
              final last = _lastUpdateAt(service) ?? service.completedAt;
              final dateText = last == null ? '—' : df.format(last);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(_typeIcon(service.serviceType)),
                    title: Text(
                      '${service.customerName} · ${service.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_statusLabel(service.status)} · ${_typeLabel(service.serviceType)} · P${service.priority}\nÚltimo: $dateText',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openDetail(service),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AgendaTab extends StatelessWidget {
  final List<ServiceModel> services;
  final void Function(ServiceModel) onOpenService;
  final Future<bool> Function(_CreateServiceDraft draft, String kind)
  onCreateFromAgenda;

  const _AgendaTab({
    required this.services,
    required this.onOpenService,
    required this.onCreateFromAgenda,
  });

  @override
  Widget build(BuildContext context) {
    final scheduled =
        services.where((item) => item.scheduledStart != null).toList()
          ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
    final dateFormat = DateFormat('EEE dd/MM HH:mm', 'es');
    final isCompact = MediaQuery.sizeOf(context).width < 420;

    Widget headerCard() {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Agenda de Servicios',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openHistorialDialog(context),
                    icon: const Icon(Icons.history),
                    label: const Text('Historial'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Registrar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _quickCreateButton(
                    context,
                    label: 'Orden',
                    icon: Icons.add_task_rounded,
                    kind: 'mantenimiento',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      children: [
        headerCard(),
        const SizedBox(height: 10),
        if (scheduled.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('Sin servicios agendados en el rango seleccionado'),
            ),
          )
        else
          ...scheduled.map((service) {
            final techs = service.assignments.map((a) => a.userName).join(', ');
            final subtitle =
                '${dateFormat.format(service.scheduledStart!)} · ${service.status}\n'
                '${techs.isEmpty ? 'Sin técnicos' : techs}'
                '${isCompact ? '\n${service.serviceType} · P${service.priority}' : ''}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  dense: isCompact,
                  isThreeLine: true,
                  onTap: () => onOpenService(service),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${service.customerName} · ${service.title}',
                          maxLines: isCompact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (service.isSeguro) ...[
                        const SizedBox(width: 8),
                        const _SeguroBadge(),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: isCompact ? 3 : 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCompact
                      ? null
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(service.serviceType),
                            Text('P${service.priority}'),
                          ],
                        ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _quickCreateButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String kind,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _openCreateSheet(context, kind),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _openCreateSheet(BuildContext context, String kind) async {
    const title = 'Crear orden de servicio';
    const submitLabel = 'Guardar orden';
    const initialServiceType = 'maintenance';

    var selectedKind = kind;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.92,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Text(
                        'Crea una orden genérica. La etapa se puede ajustar luego en Detalles.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('agenda-create-kind-$selectedKind'),
                        initialValue: selectedKind,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Fase de orden',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'reserva',
                            child: Text('Reserva'),
                          ),
                          DropdownMenuItem(
                            value: 'instalacion',
                            child: Text('Instalación'),
                          ),
                          DropdownMenuItem(
                            value: 'mantenimiento',
                            child: Text('Mantenimiento'),
                          ),
                          DropdownMenuItem(
                            value: 'garantia',
                            child: Text('Garantía'),
                          ),
                          DropdownMenuItem(
                            value: 'levantamiento',
                            child: Text('Levantamiento'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => selectedKind = value);
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _CreateReservationTab(
                        onCreate: (draft) async {
                          final ok = await onCreateFromAgenda(
                            draft,
                            selectedKind,
                          );
                          if (ok && context.mounted) Navigator.pop(context);
                        },
                        submitLabel: submitLabel,
                        initialServiceType: initialServiceType,
                        showServiceTypeField: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openHistorialDialog(BuildContext context) async {
    final items = [...services];
    items.sort((a, b) {
      final ad = a.scheduledStart ?? a.completedAt;
      final bd = b.scheduledStart ?? b.completedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    final df = DateFormat('dd/MM/yyyy HH:mm', 'es');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Historial de servicios (${items.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('Sin servicios para mostrar'),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final service = items[index];
                              final date =
                                  service.scheduledStart ?? service.completedAt;
                              final dateText = date == null
                                  ? '—'
                                  : df.format(date);
                              return ListTile(
                                title: Text(
                                  '${service.customerName} · ${service.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '$dateText · ${service.status} · ${service.serviceType} · P${service.priority}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  onOpenService(service);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CreateServiceDraft {
  final String customerId;
  final String serviceType;
  final String category;
  final int priority;
  final DateTime? reservationAt;
  final String title;
  final String description;
  final String? addressSnapshot;
  final String orderState;
  final String? technicianId;
  final String? relatedServiceId;
  final String? surveyResult;
  final String? materialsUsed;
  final double? finalCost;
  final double? quotedAmount;
  final double? depositAmount;
  final List<String> tags;
  final PlatformFile? referencePhoto;

  _CreateServiceDraft({
    required this.customerId,
    required this.serviceType,
    required this.category,
    required this.priority,
    this.reservationAt,
    required this.title,
    required this.description,
    required this.orderState,
    this.technicianId,
    this.addressSnapshot,
    this.relatedServiceId,
    this.surveyResult,
    this.materialsUsed,
    this.finalCost,
    this.quotedAmount,
    this.depositAmount,
    this.tags = const [],
    this.referencePhoto,
  });
}

class _CreateReservationTab extends ConsumerStatefulWidget {
  final Future<void> Function(_CreateServiceDraft draft) onCreate;
  final String submitLabel;
  final String initialServiceType;
  final bool showServiceTypeField;
  final String? agendaKind;

  const _CreateReservationTab({
    // ignore: unused_element_parameter
    super.key,
    required this.onCreate,
    this.submitLabel = 'Guardar reserva',
    this.initialServiceType = 'installation',
    this.showServiceTypeField = true,
    // ignore: unused_element_parameter
    this.agendaKind,
  });

  @override
  ConsumerState<_CreateReservationTab> createState() =>
      _CreateReservationTabState();
}

class _CreateReservationTabState extends ConsumerState<_CreateReservationTab> {
  final _formKey = GlobalKey<FormState>();
  final _searchClientCtrl = TextEditingController();
  final _reservationDateCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gpsCtrl = TextEditingController();
  final _quotedCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _relatedServiceCtrl = TextEditingController();
  final _surveyResultCtrl = TextEditingController();
  final _materialsUsedCtrl = TextEditingController();
  final _finalCostCtrl = TextEditingController();

  late String _serviceType;
  late String _category;
  late int _priority;
  late String _orderState;
  String? _technicianId;
  bool _priorityTouched = false;
  bool _loadingTechnicians = false;
  List<TechnicianModel> _technicians = const [];
  String? _customerId;
  String? _customerName;
  String? _customerPhone;
  DateTime? _reservationAt;
  bool _checkingCotizaciones = false;
  bool _hasCotizaciones = false;
  CotizacionModel? _selectedCotizacion;

  String _cotizacionesRouteForSelectedClient() {
    final id = (_customerId ?? '').trim();
    final name = (_customerName ?? '').trim();
    final phone = (_customerPhone ?? '').trim();

    final params = <String, String>{
      // Cuando se abre Cotizaciones desde Agenda, al guardar debe regresar.
      'popOnSave': '1',
    };
    if (id.isNotEmpty) params['customerId'] = id;
    if (name.isNotEmpty) params['customerName'] = name;
    if (phone.isNotEmpty) params['customerPhone'] = phone;

    final q = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '${Routes.cotizaciones}?$q';
  }

  LatLng? _gpsPoint;
  Timer? _gpsResolveDebounce;
  bool _resolvingGps = false;
  int _gpsResolveSeq = 0;
  PlatformFile? _referencePhoto;
  bool _saving = false;

  bool get _isAgendaReserva {
    final k = (widget.agendaKind ?? '').trim().toLowerCase();
    return k == 'reserva';
  }

  String? _requiredPriceValidator(String? _) {
    if (!_isAgendaReserva) return null;
    final raw = _quotedCtrl.text.trim();
    if (raw.isEmpty) return 'Requerido';
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return 'Requerido';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _serviceType = widget.initialServiceType;
    _category = 'cameras';
    _priority = 1;
    _orderState = 'pendiente';
    _applyDefaultsForKind(widget.agendaKind, kindChanged: true);
    Future.microtask(_loadTechnicians);
  }

  @override
  void didUpdateWidget(covariant _CreateReservationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKind = (oldWidget.agendaKind ?? '').trim().toLowerCase();
    final newKind = (widget.agendaKind ?? '').trim().toLowerCase();
    if (oldKind != newKind) {
      _applyDefaultsForKind(widget.agendaKind, kindChanged: true);
    }

    if (!widget.showServiceTypeField &&
        oldWidget.initialServiceType != widget.initialServiceType) {
      final next = widget.initialServiceType;
      if (_serviceType != next) {
        setState(() => _serviceType = next);
      }
    }
  }

  @override
  void dispose() {
    _searchClientCtrl.dispose();
    _reservationDateCtrl.dispose();
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _gpsCtrl.dispose();
    _gpsResolveDebounce?.cancel();
    _quotedCtrl.dispose();
    _depositCtrl.dispose();
    _relatedServiceCtrl.dispose();
    _surveyResultCtrl.dispose();
    _materialsUsedCtrl.dispose();
    _finalCostCtrl.dispose();
    super.dispose();
  }

  void _applyDefaultsForKind(String? kind, {required bool kindChanged}) {
    final lower = (kind ?? '').trim().toLowerCase();

    final hasTech = (_technicianId ?? '').trim().isNotEmpty;
    final nextState = hasTech ? 'asignada' : 'pendiente';

    final nextPriority = (!_priorityTouched && lower == 'garantia')
        ? 1
        : _priority;

    if (!mounted) {
      _orderState = nextState;
      _priority = nextPriority;
      return;
    }

    setState(() {
      _orderState = nextState;
      _priority = nextPriority;
    });
  }

  Future<void> _loadTechnicians() async {
    if (_loadingTechnicians) return;
    setState(() => _loadingTechnicians = true);
    try {
      final items = await ref
          .read(operationsRepositoryProvider)
          .listTechnicians();
      if (!mounted) return;
      setState(() => _technicians = items);
    } catch (_) {
      // Silencioso: el formulario funciona igual sin dropdown.
    } finally {
      if (mounted) setState(() => _loadingTechnicians = false);
    }
  }

  bool _looksLikeHttpUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    final uri = Uri.tryParse(v);
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  LatLng? _extractLatLngByRegex(String text) {
    final patterns = <RegExp>[
      RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      RegExp(r'center=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      RegExp(r'll=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      RegExp(r'q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
      // Google Maps place URLs often include coords as: ...!3dLAT!4dLNG...
      RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m == null) continue;
      final lat = double.tryParse(m.group(1) ?? '');
      final lng = double.tryParse(m.group(2) ?? '');
      if (lat == null || lng == null) continue;
      return LatLng(lat, lng);
    }
    return null;
  }

  String? _extractGoogleMapsUrlFromHtml(String html) {
    final candidates = <RegExp>[
      RegExp(r'https?://www\.google\.com/maps[^\"\s<]+'),
      RegExp(r'https?://maps\.google\.com/\?[^\"\s<]+'),
      RegExp(r'https?://google\.com/maps[^\"\s<]+'),
    ];
    for (final re in candidates) {
      final m = re.firstMatch(html);
      if (m == null) continue;
      return m.group(0);
    }
    return null;
  }

  Future<LatLng?> _resolveLatLngFromText(String value) async {
    final direct = parseLatLngFromText(value);
    if (direct != null) return direct;

    if (!_looksLikeHttpUrl(value)) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;

    try {
      final dio = Dio(
        BaseOptions(
          followRedirects: true,
          maxRedirects: 8,
          connectTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 500,
        ),
      );

      final response = await dio.getUri(uri);
      final resolvedUrl = response.realUri.toString();

      final fromResolvedUrl = parseLatLngFromText(resolvedUrl);
      if (fromResolvedUrl != null) return fromResolvedUrl;

      final fromResolvedUrlRegex = _extractLatLngByRegex(resolvedUrl);
      if (fromResolvedUrlRegex != null) return fromResolvedUrlRegex;

      final body = response.data?.toString() ?? '';
      final fromBody = _extractLatLngByRegex(body);
      if (fromBody != null) return fromBody;

      final embeddedMapsUrl = _extractGoogleMapsUrlFromHtml(body);
      if (embeddedMapsUrl != null) {
        final fromEmbeddedUrl = parseLatLngFromText(embeddedMapsUrl);
        if (fromEmbeddedUrl != null) return fromEmbeddedUrl;

        final fromEmbeddedUrlRegex = _extractLatLngByRegex(embeddedMapsUrl);
        if (fromEmbeddedUrlRegex != null) return fromEmbeddedUrlRegex;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveAndSetGpsPoint(
    String raw, {
    bool showSnackOnFail = false,
  }) async {
    final text = raw.trim();
    if (text.isEmpty) return;

    final seq = ++_gpsResolveSeq;
    if (mounted) {
      setState(() => _resolvingGps = true);
    }

    final point = await _resolveLatLngFromText(text);

    if (!mounted) return;
    if (seq != _gpsResolveSeq) return;

    setState(() {
      _resolvingGps = false;
      if (point != null) _gpsPoint = point;
    });

    if (point == null && showSnackOnFail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pude detectar coordenadas. Prueba pegar un link que incluya lat,lng (o pega "lat,lng" directamente).',
          ),
        ),
      );
    }
  }

  void _openGpsFullScreen(LatLng point) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _AgendaGpsFullMapScreen(
          point: point,
          title: _customerName ?? 'Ubicación',
        ),
      ),
    );
  }

  String _serviceTypeLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'installation':
        return 'Instalación';
      case 'maintenance':
        return 'Mantenimiento';
      case 'warranty':
        return 'Garantía';
      case 'pos_support':
        return 'Soporte POS';
      default:
        return 'Servicio';
    }
  }

  String _categoryLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'cameras':
        return 'Cámaras';
      case 'gate_motor':
        return 'Motores de puertones';
      case 'alarm':
        return 'Alarma';
      case 'electric_fence':
        return 'Cerco eléctrico';
      case 'intercom':
        return 'Intercom';
      case 'pos':
        return 'Punto de ventas';
      default:
        return raw.trim().isEmpty ? 'General' : raw.trim();
    }
  }

  Future<void> _pickReferencePhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _referencePhoto = result.files.first);
  }

  Future<void> _pasteGpsFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isEmpty) return;

    final parsed = parseLatLngFromText(text);
    setState(() {
      _gpsCtrl.text = text;
      _gpsPoint = parsed;
    });

    if (parsed == null) {
      await _resolveAndSetGpsPoint(text, showSnackOnFail: true);
    }
  }

  Future<void> _openGpsInApp() async {
    final point = _gpsPoint ?? parseLatLngFromText(_gpsCtrl.text);
    if (point != null) {
      _openGpsFullScreen(point);
      return;
    }

    await _resolveAndSetGpsPoint(_gpsCtrl.text, showSnackOnFail: true);
    final resolved = _gpsPoint;
    if (!mounted || resolved == null) return;
    _openGpsFullScreen(resolved);
  }

  String? _buildAddressSnapshot() {
    final address = _addressCtrl.text.trim();
    final gpsText = _gpsCtrl.text.trim();
    final point = _gpsPoint ?? parseLatLngFromText(_gpsCtrl.text);

    final hasAddress = address.isNotEmpty;
    final hasPoint = point != null;
    final hasGpsText = gpsText.isNotEmpty;

    if (!hasAddress && !hasPoint) return null;
    if (!hasPoint) {
      if (!hasAddress && !hasGpsText) return null;
      if (!hasGpsText) return address;

      final isUrl = RegExp(
        r'https?://',
        caseSensitive: false,
      ).hasMatch(gpsText);
      final lines = <String>[];
      if (hasAddress) lines.add(address);
      lines.add(isUrl ? 'MAPS: $gpsText' : 'GPS: $gpsText');
      return lines.join('\n');
    }

    final gpsLine = 'GPS: ${formatLatLng(point)}';
    final mapsLine = 'MAPS: ${buildGoogleMapsSearchUrl(point)}';

    final lines = <String>[];
    if (hasAddress) lines.add(address);
    lines.add(gpsLine);
    lines.add(mapsLine);
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 430;
        final formPadding = isCompact ? 10.0 : 14.0;

        String money(double value) => NumberFormat.currency(
          locale: 'es_DO',
          symbol: 'RD\$',
        ).format(value);

        return Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(formPadding),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cliente',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _customerName == null
                                  ? 'Sin cliente seleccionado'
                                  : _customerName!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_customerName != null) ...[
                              const SizedBox(height: 8),
                              if (_checkingCotizaciones)
                                const SizedBox(
                                  width: 160,
                                  child: LinearProgressIndicator(minHeight: 2),
                                )
                              else if (_hasCotizaciones)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final phone = (_customerPhone ?? '')
                                          .trim();
                                      if (phone.isEmpty) return;
                                      context.push(
                                        '${Routes.cotizacionesHistorial}?customerPhone=${Uri.encodeQueryComponent(phone)}&pick=0',
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.receipt_long_outlined,
                                    ),
                                    label: const Text('Ver cotizaciones'),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _openClientPicker,
                            icon: const Icon(Icons.person_search_outlined),
                            label: const Text('Cliente'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: (_customerId ?? '').trim().isEmpty
                                ? null
                                : () async {
                                    final id = _customerId!;
                                    await context.push(Routes.clienteEdit(id));
                                    if (!mounted) return;
                                    await _openClientPicker();
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Editar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_customerName != null) ...[
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Cotización',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedCotizacion == null
                              ? (_hasCotizaciones
                                    ? 'Selecciona una cotización o crea una nueva.'
                                    : 'Este cliente no tiene cotizaciones guardadas.')
                              : 'Seleccionada: ${money(_selectedCotizacion!.total)} · ${DateFormat('dd/MM/yyyy HH:mm').format(_selectedCotizacion!.createdAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: (_customerPhone ?? '').trim().isEmpty
                                  ? null
                                  : () async {
                                      final picked =
                                          await _openCotizacionPickerDialog();
                                      if (!mounted || picked == null) return;
                                      setState(() {
                                        _selectedCotizacion = picked;
                                        _quotedCtrl.text = picked.total
                                            .toStringAsFixed(2);
                                      });
                                    },
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Seleccionar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await context.push(
                                  _cotizacionesRouteForSelectedClient(),
                                );
                                if (!mounted) return;
                                await _checkCotizacionesForSelectedClient();
                                final picked =
                                    await _openCotizacionPickerDialog();
                                if (!mounted || picked == null) return;
                                setState(() {
                                  _selectedCotizacion = picked;
                                  _quotedCtrl.text = picked.total
                                      .toStringAsFixed(2);
                                });
                              },
                              icon: const Icon(Icons.add_box_outlined),
                              label: const Text('Crear'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _reservationDateCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Fecha y hora',
                  suffixIcon: Icon(Icons.schedule_outlined),
                ),
                validator: (_) {
                  return _reservationAt == null ? 'Requerido' : null;
                },
                onTap: _pickReservationDate,
              ),
              const SizedBox(height: 10),
              if (isCompact) ...[
                if (widget.showServiceTypeField) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _serviceType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Tipo de servicio',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'installation',
                        child: Text('Instalación'),
                      ),
                      DropdownMenuItem(
                        value: 'maintenance',
                        child: Text('Mantenimiento'),
                      ),
                      DropdownMenuItem(
                        value: 'warranty',
                        child: Text('Garantía'),
                      ),
                      DropdownMenuItem(
                        value: 'pos_support',
                        child: Text('Soporte POS'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Otro')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _serviceType = value;
                        if (value == 'installation') _priority = 1;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Categoría',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cameras', child: Text('Cámaras')),
                    DropdownMenuItem(
                      value: 'gate_motor',
                      child: Text('Motores de puertones'),
                    ),
                    DropdownMenuItem(value: 'alarm', child: Text('Alarma')),
                    DropdownMenuItem(
                      value: 'electric_fence',
                      child: Text('Cerco eléctrico'),
                    ),
                    DropdownMenuItem(
                      value: 'intercom',
                      child: Text('Intercom'),
                    ),
                    DropdownMenuItem(
                      value: 'pos',
                      child: Text('Punto de ventas'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
              ] else ...[
                if (widget.showServiceTypeField)
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _serviceType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Tipo de servicio',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'installation',
                              child: Text('Instalación'),
                            ),
                            DropdownMenuItem(
                              value: 'maintenance',
                              child: Text('Mantenimiento'),
                            ),
                            DropdownMenuItem(
                              value: 'warranty',
                              child: Text('Garantía'),
                            ),
                            DropdownMenuItem(
                              value: 'pos_support',
                              child: Text('Soporte POS'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text('Otro'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _serviceType = value;
                              if (value == 'installation') _priority = 1;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Categoría',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'cameras',
                              child: Text('Cámaras'),
                            ),
                            DropdownMenuItem(
                              value: 'gate_motor',
                              child: Text('Motores de puertones'),
                            ),
                            DropdownMenuItem(
                              value: 'alarm',
                              child: Text('Alarma'),
                            ),
                            DropdownMenuItem(
                              value: 'electric_fence',
                              child: Text('Cerco eléctrico'),
                            ),
                            DropdownMenuItem(
                              value: 'intercom',
                              child: Text('Intercom'),
                            ),
                            DropdownMenuItem(
                              value: 'pos',
                              child: Text('Punto de ventas'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _category = value);
                            }
                          },
                        ),
                      ),
                    ],
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Categoría',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'cameras',
                        child: Text('Cámaras'),
                      ),
                      DropdownMenuItem(
                        value: 'gate_motor',
                        child: Text('Motores de puertones'),
                      ),
                      DropdownMenuItem(value: 'alarm', child: Text('Alarma')),
                      DropdownMenuItem(
                        value: 'electric_fence',
                        child: Text('Cerco eléctrico'),
                      ),
                      DropdownMenuItem(
                        value: 'intercom',
                        child: Text('Intercom'),
                      ),
                      DropdownMenuItem(
                        value: 'pos',
                        child: Text('Punto de ventas'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
                    },
                  ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _priority,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Prioridad',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Alta')),
                  DropdownMenuItem(value: 2, child: Text('Media')),
                  DropdownMenuItem(value: 3, child: Text('Baja')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _priority = value;
                      _priorityTouched = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('orderState-$_orderState'),
                initialValue: _orderState,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Estado (auto)',
                  helperText: 'Se calcula automáticamente al asignar técnico.',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'pendiente',
                    child: Text('Pendiente'),
                  ),
                  DropdownMenuItem(
                    value: 'confirmada',
                    child: Text('Confirmada'),
                  ),
                  DropdownMenuItem(value: 'asignada', child: Text('Asignada')),
                  DropdownMenuItem(
                    value: 'en_camino',
                    child: Text('En camino'),
                  ),
                  DropdownMenuItem(
                    value: 'en_proceso',
                    child: Text('En proceso'),
                  ),
                  DropdownMenuItem(
                    value: 'finalizada',
                    child: Text('Finalizada'),
                  ),
                  DropdownMenuItem(
                    value: 'cancelada',
                    child: Text('Cancelada'),
                  ),
                  DropdownMenuItem(
                    value: 'reagendada',
                    child: Text('Reagendada'),
                  ),
                  DropdownMenuItem(value: 'cerrada', child: Text('Cerrada')),
                ],
                onChanged: null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey('technician-${_technicianId ?? ''}'),
                initialValue: _technicianId ?? '',
                isExpanded: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Técnico asignado',
                  helperText: _loadingTechnicians
                      ? 'Cargando técnicos...'
                      : (_technicians.isEmpty
                            ? 'No tienes técnicos registrados. Puedes guardar sin asignar.'
                            : null),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Sin asignar')),
                  ..._technicians.map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                  ),
                ],
                onChanged: _loadingTechnicians
                    ? null
                    : (value) {
                        if (value == null || value.trim().isEmpty) {
                          setState(() => _technicianId = null);
                        } else {
                          setState(() => _technicianId = value);
                        }

                        _applyDefaultsForKind(
                          widget.agendaKind,
                          kindChanged: false,
                        );
                      },
              ),
              if (!_loadingTechnicians && _technicians.isEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'No tienes técnicos registrados.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => context.push(Routes.users),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Crear técnico'),
                    ),
                  ],
                ),
              ],
              Builder(
                builder: (context) {
                  final kind = (widget.agendaKind ?? '').trim().toLowerCase();

                  if (kind == 'garantia') {
                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _relatedServiceCtrl,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText:
                                'Orden anterior / Servicio relacionado (opcional)',
                          ),
                        ),
                      ],
                    );
                  }

                  if (kind == 'levantamiento') {
                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _surveyResultCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Resultado del levantamiento (opcional)',
                          ),
                        ),
                      ],
                    );
                  }

                  if (kind == 'servicio') {
                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _materialsUsedCtrl,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Material usado (opcional)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _finalCostCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Costo final (opcional)',
                          ),
                        ),
                      ],
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Foto de referencia (casa)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _referencePhoto == null
                            ? 'Opcional: sube una foto para ubicar la casa más rápido.'
                            : 'Seleccionada: ${_referencePhoto!.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_referencePhoto != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.25),
                                ),
                              ),
                              child: (_referencePhoto!.bytes != null)
                                  ? Image.memory(
                                      _referencePhoto!.bytes!,
                                      fit: BoxFit.cover,
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.image_outlined,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.65),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickReferencePhoto,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: Text(
                              _referencePhoto == null ? 'Agregar' : 'Cambiar',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _referencePhoto == null
                                ? null
                                : () => setState(() => _referencePhoto = null),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Quitar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Dirección (ciudad/sector)',
                  helperText: 'Ej: Higüey, Otra Banda, Miches',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _gpsCtrl,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Ubicación GPS (WhatsApp/Maps)',
                  helperText: _resolvingGps
                      ? 'Detectando ubicación desde el link...'
                      : (_gpsPoint == null
                            ? 'Pega un link de Google Maps o "lat,lng"'
                            : 'Detectado: ${formatLatLng(_gpsPoint!)}'),
                  suffixIcon: SizedBox(
                    width: 96,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Pegar',
                          onPressed: _pasteGpsFromClipboard,
                          icon: const Icon(Icons.content_paste_rounded),
                        ),
                        IconButton(
                          tooltip: 'Ver mapa',
                          onPressed: _gpsCtrl.text.trim().isEmpty
                              ? null
                              : _openGpsInApp,
                          icon: const Icon(Icons.map_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                onChanged: (value) {
                  final parsed = parseLatLngFromText(value);
                  setState(() => _gpsPoint = parsed);
                  if (parsed != null) return;

                  if (!_looksLikeHttpUrl(value)) return;
                  _gpsResolveDebounce?.cancel();
                  _gpsResolveDebounce = Timer(
                    const Duration(milliseconds: 650),
                    () => _resolveAndSetGpsPoint(value),
                  );
                },
              ),
              if (_gpsPoint != null) ...[
                const SizedBox(height: 10),
                _GpsMapPreviewCard(
                  point: _gpsPoint!,
                  onOpen: () {
                    final point = _gpsPoint;
                    if (point == null) return;
                    _openGpsFullScreen(point);
                  },
                  onNavigate: () {
                    final point = _gpsPoint;
                    if (point == null) return;
                    _openBestNavigation(context, point);
                  },
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Nota (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              if (isCompact) ...[
                TextFormField(
                  controller: _quotedCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Precio vendido',
                  ),
                  validator: _requiredPriceValidator,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _depositCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Abono (señal)',
                    helperText: 'Si hay abono, se marca como SEGURO',
                  ),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quotedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Precio vendido',
                        ),
                        validator: _requiredPriceValidator,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _depositCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Abono (señal)',
                          helperText: 'Si hay abono, se marca como SEGURO',
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando...' : widget.submitLabel),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openClientPicker() async {
    final selected = await _openClientPickerDialog();
    if (!mounted || selected == null) return;
    setState(() {
      _customerId = selected.id;
      _customerName = selected.nombre;
      _customerPhone = selected.telefono;
      _addressCtrl.text = selected.direccion ?? '';
      _selectedCotizacion = null;
      _hasCotizaciones = false;
    });

    // Evita arrastrar precio/cotización de un cliente anterior.
    _quotedCtrl.clear();

    await _checkCotizacionesForSelectedClient();
  }

  Future<void> _pickReservationDate() async {
    final now = DateTime.now();
    final initial = _reservationAt ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (!mounted || pickedDate == null) return;

    final initialTimeSource = _reservationAt ?? DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialTimeSource),
    );
    if (!mounted || pickedTime == null) return;

    final next = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      _reservationAt = next;
      _reservationDateCtrl.text = DateFormat('dd/MM/yyyy HH:mm').format(next);
    });
  }

  Future<CotizacionModel?> _openCotizacionPickerDialog() async {
    final phone = (_customerPhone ?? '').trim();
    if (phone.isEmpty) return null;

    return showDialog<CotizacionModel>(
      context: context,
      builder: (context) {
        var loading = true;
        String? error;
        List<CotizacionModel> items = const [];
        var didInit = false;

        String money(double value) => NumberFormat.currency(
          locale: 'es_DO',
          symbol: 'RD\$',
        ).format(value);

        Future<void> load(StateSetter setDialogState) async {
          setDialogState(() {
            loading = true;
            error = null;
          });
          try {
            final rows = await ref
                .read(cotizacionesRepositoryProvider)
                .list(customerPhone: phone);
            if (!context.mounted) return;
            setDialogState(() {
              items = rows;
              loading = false;
            });
          } catch (e) {
            if (!context.mounted) return;
            setDialogState(() {
              error = e is ApiException ? e.message : '$e';
              loading = false;
            });
          }
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                if (!didInit) {
                  didInit = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    load(setDialogState);
                  });
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Seleccionar cotización',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Cliente: ${_customerName ?? '—'} · $phone',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: loading
                                ? null
                                : () => load(setDialogState),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Recargar'),
                          ),
                        ],
                      ),
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: items.isEmpty
                            ? const Center(
                                child: Text('No hay cotizaciones para mostrar'),
                              )
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    title: Text(
                                      money(item.total),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      DateFormat(
                                        'dd/MM/yyyy HH:mm',
                                      ).format(item.createdAt),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.pop(context, item),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push(_cotizacionesRouteForSelectedClient());
                        },
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('Crear nueva cotización'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkCotizacionesForSelectedClient() async {
    final phone = (_customerPhone ?? '').trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      setState(() {
        _hasCotizaciones = false;
        _checkingCotizaciones = false;
        _selectedCotizacion = null;
      });
      return;
    }

    setState(() => _checkingCotizaciones = true);
    try {
      final rows = await ref
          .read(cotizacionesRepositoryProvider)
          .list(customerPhone: phone, take: 1);
      if (!mounted) return;
      final latest = rows.isEmpty ? null : rows.first;
      setState(() {
        _hasCotizaciones = latest != null;

        // Por defecto, toma el precio vendido del total de la última cotización.
        // No pisa si el usuario ya escribió un precio.
        if (latest != null && _selectedCotizacion == null) {
          _selectedCotizacion = latest;
          if (_quotedCtrl.text.trim().isEmpty) {
            _quotedCtrl.text = latest.total.toStringAsFixed(2);
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasCotizaciones = false);
    } finally {
      if (mounted) setState(() => _checkingCotizaciones = false);
    }
  }

  Future<ClienteModel?> _openClientPickerDialog() async {
    return showDialog<ClienteModel>(
      context: context,
      builder: (context) {
        final queryCtrl = TextEditingController(text: _searchClientCtrl.text);
        var loading = false;
        var items = <ClienteModel>[];
        var didInitLoad = false;

        Future<void> runSearch(StateSetter setDialogState) async {
          final query = queryCtrl.text.trim();
          setDialogState(() => loading = true);
          try {
            final results = await ref
                .read(operationsControllerProvider.notifier)
                .searchClients(query);
            if (!context.mounted) return;
            setDialogState(() => items = results);
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e is ApiException ? e.message : '$e')),
            );
          } finally {
            if (context.mounted) setDialogState(() => loading = false);
          }
        }

        Future<void> addNewClient(StateSetter setDialogState) async {
          final created = await _promptNewClientDialog();
          if (!context.mounted || created == null) return;
          Navigator.pop(context, created);
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                if (!didInitLoad) {
                  didInitLoad = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    runSearch(setDialogState);
                  });
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Cliente',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: queryCtrl,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Buscar cliente',
                              ),
                              onSubmitted: (_) => runSearch(setDialogState),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: loading
                                ? null
                                : () => runSearch(setDialogState),
                            icon: const Icon(Icons.search),
                            label: const Text('Buscar'),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: loading
                              ? null
                              : () => addNewClient(setDialogState),
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Agregar cliente'),
                        ),
                      ),
                      if (loading) const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      Expanded(
                        child: items.isEmpty
                            ? const Center(
                                child: Text('Sin clientes para mostrar'),
                              )
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    title: Text(item.nombre),
                                    subtitle: Text(item.telefono),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.pop(context, item),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<ClienteModel?> _promptNewClientDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok != true) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      return null;
    }

    try {
      final created = await ref
          .read(operationsControllerProvider.notifier)
          .createQuickClient(
            nombre: nameCtrl.text.trim(),
            telefono: phoneCtrl.text.trim(),
          );
      return created;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
      return null;
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    }
  }

  Future<void> _save() async {
    if (_customerId == null || _customerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente primero')),
      );
      return;
    }

    if (_category.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La categoría es requerida')),
      );
      return;
    }

    if (_priority < 1 || _priority > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La prioridad es requerida')),
      );
      return;
    }

    if (_isAgendaReserva) {
      final phone = (_customerPhone ?? '').trim();
      if (phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El cliente debe tener teléfono')),
        );
        return;
      }

      if (_selectedCotizacion == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona o crea una cotización')),
        );
        return;
      }
    }

    if (!_formKey.currentState!.validate()) return;

    final quoted = double.tryParse(_quotedCtrl.text.trim());
    final deposit = double.tryParse(_depositCtrl.text.trim());
    if ((deposit ?? 0) > 0) {
      if (quoted == null || quoted <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Si hay abono, el precio vendido es requerido'),
          ),
        );
        return;
      }
      if (deposit! > quoted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El abono no puede ser mayor que el precio vendido'),
          ),
        );
        return;
      }
    }

    final tags = <String>[];
    if ((deposit ?? 0) > 0) tags.add('seguro');

    setState(() => _saving = true);
    try {
      final gpsText = _gpsCtrl.text.trim();
      if (gpsText.isNotEmpty && _gpsPoint == null && !_resolvingGps) {
        setState(() => _resolvingGps = true);
        try {
          final point = await _resolveLatLngFromText(gpsText);
          if (!mounted) return;
          setState(() {
            _resolvingGps = false;
            if (point != null) _gpsPoint = point;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() => _resolvingGps = false);
        }
      }

      final title =
          '${_serviceTypeLabel(_serviceType)} · ${_categoryLabel(_category)}';
      final note = _descriptionCtrl.text.trim();
      final description = note.isEmpty ? 'Sin nota' : note;
      final reservationAt = _reservationAt;

      await widget.onCreate(
        _CreateServiceDraft(
          customerId: _customerId!,
          serviceType: _serviceType,
          category: _category,
          priority: _priority,
          reservationAt: reservationAt,
          title: title,
          description: description,
          orderState: _orderState,
          technicianId: _technicianId,
          addressSnapshot: _buildAddressSnapshot(),
          relatedServiceId: _relatedServiceCtrl.text.trim().isEmpty
              ? null
              : _relatedServiceCtrl.text.trim(),
          surveyResult: _surveyResultCtrl.text.trim().isEmpty
              ? null
              : _surveyResultCtrl.text.trim(),
          materialsUsed: _materialsUsedCtrl.text.trim().isEmpty
              ? null
              : _materialsUsedCtrl.text.trim(),
          finalCost: double.tryParse(_finalCostCtrl.text.trim()),
          quotedAmount: quoted,
          depositAmount: deposit,
          tags: tags,
          referencePhoto: _referencePhoto,
        ),
      );
      if (!mounted) return;
      _formKey.currentState!.reset();
      _reservationDateCtrl.clear();
      _reservationAt = null;
      _descriptionCtrl.clear();
      _addressCtrl.clear();
      _gpsCtrl.clear();
      _gpsPoint = null;
      _referencePhoto = null;
      _orderState = 'pendiente';
      _technicianId = null;
      _priorityTouched = false;
      _relatedServiceCtrl.clear();
      _surveyResultCtrl.clear();
      _materialsUsedCtrl.clear();
      _finalCostCtrl.clear();
      _quotedCtrl.clear();
      _depositCtrl.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // _createQuickClient() eliminado: ahora se maneja desde el diálogo de Cliente.
}

class _PunchOnlySheet extends ConsumerWidget {
  const _PunchOnlySheet();

  static IconData _iconFor(PunchType type) {
    return switch (type) {
      PunchType.entradaLabor => Icons.login,
      PunchType.salidaLabor => Icons.exit_to_app,
      PunchType.salidaPermiso => Icons.meeting_room_outlined,
      PunchType.entradaPermiso => Icons.door_back_door,
      PunchType.salidaAlmuerzo => Icons.fastfood,
      PunchType.entradaAlmuerzo => Icons.restaurant,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(punchControllerProvider);
    final notifier = ref.read(punchControllerProvider.notifier);
    final theme = Theme.of(context);

    Future<void> handlePunch(PunchType type) async {
      if (state.creating) return;
      try {
        await notifier.register(type);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ponche "${type.label}" registrado')),
        );
        Navigator.of(context).pop();
      } catch (e) {
        if (!context.mounted) return;
        final message = e is ApiException ? e.message : 'No se pudo ponchar';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }

    return Material(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ponchado rápido',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: state.creating
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
            Text(
              '¿Qué deseas registrar?',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (state.error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTileTheme(
                  dense: true,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                    itemCount: PunchType.values.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final type = PunchType.values[index];
                      return ListTile(
                        enabled: !state.creating,
                        leading: Icon(
                          _iconFor(type),
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(type.label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: state.creating ? null : () => handlePunch(type),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (state.creating)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogoFabIcon extends StatelessWidget {
  const _CatalogoFabIcon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = IconTheme.of(context).color ?? scheme.onPrimary;
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 24, color: color),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onPrimary.withValues(alpha: 0.18),
                border: Border.all(
                  color: scheme.onPrimary.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(Icons.search_rounded, size: 12, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PoncheFabIcon extends StatelessWidget {
  const _PoncheFabIcon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = IconTheme.of(context).color ?? scheme.onPrimary;
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.meeting_room_outlined, size: 24, color: color),
          Positioned(
            right: -2,
            bottom: -3,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onPrimary.withValues(alpha: 0.18),
                border: Border.all(
                  color: scheme.onPrimary.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Center(
                child: Transform.rotate(
                  angle: -0.12,
                  child: Icon(Icons.touch_app_outlined, size: 12, color: color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsMapPreviewCard extends StatelessWidget {
  final LatLng point;
  final VoidCallback onOpen;
  final VoidCallback onNavigate;

  const _GpsMapPreviewCard({
    required this.point,
    required this.onOpen,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 170,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: IgnorePointer(
                    ignoring: true,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 15,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'fulltech_app',
                          tileProvider: NetworkTileProvider(),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              width: 50,
                              height: 50,
                              point: point,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.35,
                                    ),
                                    size: 50,
                                  ),
                                  Icon(
                                    Icons.location_on,
                                    color: scheme.primary,
                                    size: 46,
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
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.open_in_full,
                    size: 16,
                    color: scheme.onSurface.withValues(alpha: 0.70),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ver mapa en pantalla completa',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface.withValues(alpha: 0.80),
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.directions_outlined, size: 18),
                    label: const Text('Ir'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formatLatLng(point),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openBestNavigation(BuildContext context, LatLng point) async {
  final dest = '${point.latitude},${point.longitude}';
  final googleDirectionsUrl = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(dest)}&travelmode=driving',
  );

  final wazeAppUrl = Uri.parse('waze://?ll=$dest&navigate=yes');

  Future<bool> safeLaunch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {
      // Fall through to OS-level launch.
    }
    return openUrlWithOs(uri);
  }

  void showFail(String appName) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('No se pudo abrir $appName')));
  }

  final platform = defaultTargetPlatform;
  final isDesktop =
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS;

  // Desktop UX: open the browser directly (Waze app scheme isn't expected there).
  if (isDesktop) {
    final ok = await safeLaunch(googleDirectionsUrl);
    if (!ok) showFail('Google Maps');
    return;
  }

  // One-tap behavior: prefer Waze (app), fallback to Google Maps.
  if (await safeLaunch(wazeAppUrl)) return;
  final googleUrl = platform == TargetPlatform.android
      ? Uri.parse('google.navigation:q=$dest&mode=d')
      : googleDirectionsUrl;

  final ok = await safeLaunch(googleUrl);
  if (!ok) showFail('Google Maps');
}

class _AgendaGpsFullMapScreen extends StatefulWidget {
  final LatLng point;
  final String title;

  const _AgendaGpsFullMapScreen({required this.point, required this.title});

  @override
  State<_AgendaGpsFullMapScreen> createState() =>
      _AgendaGpsFullMapScreenState();
}

class _AgendaGpsFullMapScreenState extends State<_AgendaGpsFullMapScreen> {
  final _mapController = MapController();
  LatLng? _myPoint;
  bool _locating = false;

  String get _coordsText => formatLatLng(widget.point);

  Future<void> _navigateExternal() async {
    await _openBestNavigation(context, widget.point);
  }

  Future<void> _copyCoords() async {
    await Clipboard.setData(ClipboardData(text: _coordsText));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copiado: $_coordsText')));
  }

  Future<void> _copyDirectionsLink() async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeQueryComponent(_coordsText)}&travelmode=driving',
    ).toString();
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link de navegación copiado')));
  }

  void _centerOnDestination() {
    _mapController.move(widget.point, 16);
  }

  Future<void> _centerOnMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      // On Windows desktop, location plugins can hang the app ("No responde")
      // depending on OS/location settings. Fail fast with a clear message.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ubicación no disponible en Windows. Usa Android/iOS para GPS.',
            ),
          ),
        );
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa el GPS del dispositivo')),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permiso de ubicación denegado')),
        );
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final p = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _myPoint = p);
      _mapController.move(p, 16);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener tu ubicación')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final destinationMarker = Marker(
      width: 56,
      height: 56,
      point: widget.point,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.location_on,
            color: scheme.onSurface.withValues(alpha: 0.35),
            size: 58,
          ),
          Icon(Icons.location_on, color: scheme.primary, size: 52),
        ],
      ),
    );

    final myMarker = _myPoint == null
        ? null
        : Marker(
            width: 22,
            height: 22,
            point: _myPoint!,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.secondary,
                border: Border.all(color: scheme.onSecondary, width: 2),
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Copiar coordenadas',
            onPressed: _copyCoords,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copiar link navegación',
            onPressed: _copyDirectionsLink,
            icon: const Icon(Icons.link_outlined),
          ),
          IconButton(
            tooltip: 'Ir',
            onPressed: _navigateExternal,
            icon: const Icon(Icons.directions_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: widget.point, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'fulltech_app',
                  tileProvider: NetworkTileProvider(),
                ),
                MarkerLayer(
                  markers: [destinationMarker, if (myMarker != null) myMarker],
                ),
              ],
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'gps-center-dest',
                    tooltip: 'Centrar ubicación',
                    onPressed: _centerOnDestination,
                    child: const Icon(Icons.my_location_outlined),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'gps-my-location',
                    tooltip: 'Mi ubicación',
                    onPressed: _locating ? null : _centerOnMyLocation,
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_pin_circle_outlined),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'gps-navigate',
                    tooltip: 'Ir',
                    onPressed: _navigateExternal,
                    child: const Icon(Icons.directions_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
