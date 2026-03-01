import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/punch_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../../modules/cotizaciones/cotizacion_models.dart';
import '../catalogo/catalogo_screen.dart';
import '../ponche/application/punch_controller.dart';
import 'application/operations_controller.dart';
import 'data/operations_repository.dart';
import 'operaciones_finalizados_screen.dart';
import 'operations_models.dart';
import '../../modules/clientes/cliente_model.dart';

class OperacionesScreen extends ConsumerStatefulWidget {
  const OperacionesScreen({super.key});

  @override
  ConsumerState<OperacionesScreen> createState() => _OperacionesScreenState();
}

class _OperacionesScreenState extends ConsumerState<OperacionesScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      ref.read(operationsControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final state = ref.watch(operationsControllerProvider);
    final notifier = ref.read(operationsControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

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
      drawer: AppDrawer(currentUser: authState.user),
      appBar: AppBar(
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
            tooltip: 'Agenda',
            onPressed: () => context.go(Routes.operacionesAgenda),
            icon: const Icon(Icons.event_note_rounded),
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
      ),
      floatingActionButton: Column(
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
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBoard(context, state, notifier),
    );
  }

  Widget _buildBoard(
    BuildContext context,
    OperationsState state,
    OperationsController notifier,
  ) {
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        children: [
          _PanelOptions(
            state: state,
            searchCtrl: _searchCtrl,
            onOpenService: _openServiceDetail,
          ),
        ],
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

  Future<ServiceModel> _createService(_CreateServiceDraft draft) {
    final deposit = draft.depositAmount ?? 0;
    final tags = deposit > 0 ? const ['SEGURO'] : const <String>[];
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
          tags: tags,
        );
  }

  Future<bool> _handleCreateFromAgenda(
    _CreateServiceDraft draft,
    String kind,
  ) async {
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
          );

      final reservationAt = draft.reservationAt;
      if (reservationAt != null) {
        try {
          await ref.read(operationsControllerProvider.notifier).schedule(
                created.id,
                reservationAt,
                reservationAt.add(const Duration(hours: 1)),
              );
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

  Future<void> _openAgendaForm() async {
    var kind = 'reserva';

    String titleForKind(String k) {
      final lower = k.trim().toLowerCase();
      return lower == 'reserva'
          ? 'Agendar reserva'
          : lower == 'levantamiento'
              ? 'Agendar levantamiento'
              : lower == 'servicio'
                  ? 'Agendar servicio'
                  : 'Agendar garantía';
    }

    String submitForKind(String k) {
      final lower = k.trim().toLowerCase();
      return lower == 'reserva'
          ? 'Guardar reserva'
          : lower == 'levantamiento'
              ? 'Guardar levantamiento'
              : lower == 'servicio'
                  ? 'Guardar servicio'
                  : 'Guardar garantía';
    }

    String initialServiceTypeForKind(String k) {
      final lower = k.trim().toLowerCase();
      return lower == 'garantia' ? 'warranty' : 'installation';
    }

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
                                titleForKind(kind),
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
                        child: DropdownButtonFormField<String>(
                          value: kind,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Tipo',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'reserva',
                              child: Text('Reserva'),
                            ),
                            DropdownMenuItem(
                              value: 'servicio',
                              child: Text('Servicio'),
                            ),
                            DropdownMenuItem(
                              value: 'levantamiento',
                              child: Text('Levantamiento'),
                            ),
                            DropdownMenuItem(
                              value: 'garantia',
                              child: Text('Garantía'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => kind = value);
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _CreateReservationTab(
                          key: ValueKey('agenda-form-$kind'),
                          submitLabel: submitForKind(kind),
                          initialServiceType: initialServiceTypeForKind(kind),
                          showServiceTypeField: false,
                          onCreate: (draft) async {
                            final ok = await _createFromAgenda(draft, kind);
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
                        ? const Center(child: Text('Sin servicios para mostrar'))
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final service = items[index];
                              final date = service.scheduledStart ?? service.completedAt;
                              final dateText = date == null ? '—' : df.format(date);
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
                                trailing: const Icon(Icons.chevron_right_rounded),
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

    final scheduled = state.services
        .where((s) => s.scheduledStart != null)
        .toList()
      ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
    final dateFormat = DateFormat('EEE dd/MM HH:mm', 'es');

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
                      final techs = service.assignments
                          .map((a) => a.userName)
                          .where((t) => t.trim().isNotEmpty)
                          .join(', ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: ListTile(
                            isThreeLine: true,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${service.customerName} · ${service.title}',
                                    maxLines: 2,
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
                              '${dateFormat.format(service.scheduledStart!)} · ${service.status}\n'
                              '${techs.isEmpty ? 'Sin técnicos' : techs}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              // Por ahora solo visual.
                            },
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
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.30),
        ),
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

enum _PanelStatusFilter { todos, pendientes, proceso, completadas }

enum _PanelPriorityFilter { todas, alta, normal }

class _PanelFilterResult {
  final DateTimeRange range;
  final _PanelStatusFilter status;
  final _PanelPriorityFilter priority;
  final String technicianQuery;
  final String sellerQuery;

  const _PanelFilterResult({
    required this.range,
    required this.status,
    required this.priority,
    required this.technicianQuery,
    required this.sellerQuery,
  });
}

class _PanelOptions extends StatefulWidget {
  final OperationsState state;
  final TextEditingController searchCtrl;
  final void Function(ServiceModel) onOpenService;

  const _PanelOptions({
    required this.state,
    required this.searchCtrl,
    required this.onOpenService,
  });

  @override
  State<_PanelOptions> createState() => _PanelOptionsState();
}

class _PanelOptionsState extends State<_PanelOptions> {
  DateTimeRange? _range;
  _PanelStatusFilter _statusFilter = _PanelStatusFilter.todos;
  _PanelPriorityFilter _priorityFilter = _PanelPriorityFilter.todas;
  String _technicianQuery = '';
  String _sellerQuery = '';

  DateTimeRange _todayRange() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
    );
  }

  DateTimeRange _effectiveRange() => _range ?? _todayRange();

  @override
  void initState() {
    super.initState();
    _range ??= _todayRange();
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

  DateTimeRange _normalizeRange(DateTimeRange raw) {
    final start = DateTime(raw.start.year, raw.start.month, raw.start.day);
    final end = DateTime(raw.end.year, raw.end.month, raw.end.day, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
  }

  bool _isDefaultTodayRange(DateTimeRange r) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return r.start == todayStart && r.end == todayEnd;
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

  Future<void> _openFilters() async {
    DateTimeRange range = _effectiveRange();
    var status = _statusFilter;
    var priority = _priorityFilter;
    var technicianQuery = _technicianQuery;
    var sellerQuery = _sellerQuery;

    final technicianCtrl = TextEditingController(text: technicianQuery);
    final sellerCtrl = TextEditingController(text: sellerQuery);

    final result = await showModalBottomSheet<_PanelFilterResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                Widget sectionTitle(String text) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  );
                }

                Future<void> pickCustomRange() async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange: DateTimeRange(
                      start: range.start,
                      end: range.end,
                    ),
                    helpText: 'Selecciona intervalo de fecha',
                  );
                  if (picked == null) return;
                  setSheetState(() => range = _normalizeRange(picked));
                }

                void setToday() {
                  final now = DateTime.now();
                  setSheetState(
                    () => range = DateTimeRange(
                      start: DateTime(now.year, now.month, now.day),
                      end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
                    ),
                  );
                }

                void setThisWeek() {
                  final now = DateTime.now();
                  final start = DateTime(now.year, now.month, now.day)
                      .subtract(Duration(days: now.weekday - 1));
                  final end = start.add(const Duration(days: 6));
                  setSheetState(() => range = _normalizeRange(DateTimeRange(start: start, end: end)));
                }

                void setThisMonth() {
                  final now = DateTime.now();
                  final start = DateTime(now.year, now.month, 1);
                  final end = DateTime(now.year, now.month + 1, 0);
                  setSheetState(() => range = _normalizeRange(DateTimeRange(start: start, end: end)));
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      'Filtros',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    sectionTitle('Técnico / Vendedor'),
                    TextField(
                      controller: technicianCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: 'Filtrar por técnico (nombre)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setSheetState(() => technicianQuery = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: sellerCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.storefront_outlined),
                        hintText: 'Filtrar por vendedor (creado por)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setSheetState(() => sellerQuery = v),
                    ),
                    sectionTitle('Intervalo de fecha'),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.date_range_outlined),
                        title: const Text('Rango'),
                        subtitle: Text(_rangeLabel(range)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: pickCustomRange,
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: setToday,
                          child: const Text('Hoy'),
                        ),
                        OutlinedButton(
                          onPressed: setThisWeek,
                          child: const Text('Semana'),
                        ),
                        OutlinedButton(
                          onPressed: setThisMonth,
                          child: const Text('Mes'),
                        ),
                        OutlinedButton(
                          onPressed: pickCustomRange,
                          child: const Text('Personalizado'),
                        ),
                      ],
                    ),
                    sectionTitle('Estado'),
                    Card(
                      child: Column(
                        children: [
                          RadioListTile<_PanelStatusFilter>(
                            value: _PanelStatusFilter.todos,
                            groupValue: status,
                            onChanged: (v) => setSheetState(() => status = v!),
                            title: const Text('Todos'),
                          ),
                          RadioListTile<_PanelStatusFilter>(
                            value: _PanelStatusFilter.pendientes,
                            groupValue: status,
                            onChanged: (v) => setSheetState(() => status = v!),
                            title: const Text('Pendientes'),
                          ),
                          RadioListTile<_PanelStatusFilter>(
                            value: _PanelStatusFilter.proceso,
                            groupValue: status,
                            onChanged: (v) => setSheetState(() => status = v!),
                            title: const Text('En proceso'),
                          ),
                          RadioListTile<_PanelStatusFilter>(
                            value: _PanelStatusFilter.completadas,
                            groupValue: status,
                            onChanged: (v) => setSheetState(() => status = v!),
                            title: const Text('Completadas'),
                          ),
                        ],
                      ),
                    ),
                    sectionTitle('Prioridad'),
                    Card(
                      child: Column(
                        children: [
                          RadioListTile<_PanelPriorityFilter>(
                            value: _PanelPriorityFilter.todas,
                            groupValue: priority,
                            onChanged: (v) =>
                                setSheetState(() => priority = v!),
                            title: const Text('Todas'),
                          ),
                          RadioListTile<_PanelPriorityFilter>(
                            value: _PanelPriorityFilter.alta,
                            groupValue: priority,
                            onChanged: (v) =>
                                setSheetState(() => priority = v!),
                            title: const Text('Alta prioridad'),
                          ),
                          RadioListTile<_PanelPriorityFilter>(
                            value: _PanelPriorityFilter.normal,
                            groupValue: priority,
                            onChanged: (v) =>
                                setSheetState(() => priority = v!),
                            title: const Text('Normal'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            final now = DateTime.now();
                            Navigator.pop(
                              context,
                              _PanelFilterResult(
                                range: DateTimeRange(
                                  start: DateTime(now.year, now.month, now.day),
                                  end: DateTime(
                                    now.year,
                                    now.month,
                                    now.day,
                                    23,
                                    59,
                                    59,
                                    999,
                                  ),
                                ),
                                status: _PanelStatusFilter.todos,
                                priority: _PanelPriorityFilter.todas,
                                technicianQuery: '',
                                sellerQuery: '',
                              ),
                            );
                          },
                          child: const Text('Limpiar'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              _PanelFilterResult(
                                range: range,
                                status: status,
                                priority: priority,
                                technicianQuery: technicianCtrl.text,
                                sellerQuery: sellerCtrl.text,
                              ),
                            );
                          },
                          child: const Text('Aplicar'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    technicianCtrl.dispose();
    sellerCtrl.dispose();

    if (!mounted || result == null) return;
    setState(() {
      _range = result.range;
      _statusFilter = result.status;
      _priorityFilter = result.priority;
      _technicianQuery = result.technicianQuery.trim();
      _sellerQuery = result.sellerQuery.trim();
    });
  }

  static const _pendingStatuses = {
    'reserved',
    'survey',
    'scheduled',
    'warranty',
  };
  static const _inProgressStatuses = {
    'in_progress',
  };
  static const _completedStatuses = {
    'completed',
    'closed',
  };

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

  IconData _statusIcon(String raw) {
    switch (raw) {
      case 'in_progress':
        return Icons.play_circle_outline;
      case 'completed':
      case 'closed':
        return Icons.check_circle_outline;
      default:
        return Icons.pending_outlined;
    }
  }

  Color _statusTint(BuildContext context, String raw) {
    final cs = Theme.of(context).colorScheme;
    switch (raw) {
      case 'in_progress':
        return cs.tertiary;
      case 'completed':
      case 'closed':
        return cs.primary;
      default:
        return cs.error;
    }
  }

  String _techLabel(ServiceModel s) {
    if (s.assignments.isEmpty) return 'Sin asignar';
    final tech = s.assignments
        .where((a) => a.role == 'technician')
        .cast<ServiceAssignmentModel?>()
        .firstOrNull;
    return (tech ?? s.assignments.first).userName;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final timeFormat = DateFormat('hh:mm a', 'es');
    final range = _effectiveRange();

    bool inRange(ServiceModel s) {
      final scheduled = s.scheduledStart;
      if (scheduled == null) return false;
      return !scheduled.isBefore(range.start) && !scheduled.isAfter(range.end);
    }

    final window = widget.state.services.where(inRange).toList()
      ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));

    int pendingCount(List<ServiceModel> list) =>
        list.where((s) => _pendingStatuses.contains(s.status)).length;
    int inProgressCount(List<ServiceModel> list) =>
        list.where((s) => _inProgressStatuses.contains(s.status)).length;
    int completedCount(List<ServiceModel> list) =>
        list.where((s) => _completedStatuses.contains(s.status)).length;

    final pendientesCount = pendingCount(window);
    final procesoCount = inProgressCount(window);
    final completadasCount = completedCount(window);

    final atrasadas = window.where((s) {
      final st = s.scheduledStart;
      if (st == null) return false;
      if (!_pendingStatuses.contains(s.status) &&
          !_inProgressStatuses.contains(s.status)) {
        return false;
      }
      return st.isBefore(now);
    }).length;

    final query = widget.searchCtrl.text.trim().toLowerCase();
    bool matchesQuery(ServiceModel s) {
      if (query.isEmpty) return true;
      final h = '${s.customerName} ${s.customerPhone} ${s.title}'.toLowerCase();
      return h.contains(query);
    }

    bool matchesStatus(ServiceModel s) {
      switch (_statusFilter) {
        case _PanelStatusFilter.todos:
          return true;
        case _PanelStatusFilter.pendientes:
          return _pendingStatuses.contains(s.status);
        case _PanelStatusFilter.proceso:
          return _inProgressStatuses.contains(s.status);
        case _PanelStatusFilter.completadas:
          return _completedStatuses.contains(s.status);
      }
    }

    bool matchesPriority(ServiceModel s) {
      switch (_priorityFilter) {
        case _PanelPriorityFilter.todas:
          return true;
        case _PanelPriorityFilter.alta:
          return s.priority <= 1;
        case _PanelPriorityFilter.normal:
          return s.priority > 1;
      }
    }

    bool matchesTechnician(ServiceModel s) {
      final q = _technicianQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      final names = s.assignments.map((a) => a.userName).join(' ').toLowerCase();
      return names.contains(q);
    }

    bool matchesSeller(ServiceModel s) {
      final q = _sellerQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return s.createdByName.toLowerCase().contains(q);
    }

    final filtered = window
        .where(
          (s) =>
              matchesStatus(s) &&
              matchesPriority(s) &&
              matchesTechnician(s) &&
              matchesSeller(s) &&
              matchesQuery(s),
        )
        .toList();

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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: tint, size: 18),
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
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

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
            const SizedBox(width: 10),
            summaryCard(
              label: 'En proceso',
              value: procesoCount,
              icon: Icons.play_circle_outline,
              tint: theme.colorScheme.tertiary,
              caption: _isDefaultTodayRange(range) ? 'Hoy' : null,
            ),
            const SizedBox(width: 10),
            summaryCard(
              label: 'Completadas',
              value: completadasCount,
              icon: Icons.check_circle_outline,
              tint: theme.colorScheme.primary,
              caption: _isDefaultTodayRange(range) ? 'Hoy' : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Agenda de Servicios · ${_rangeLabel(range)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.inbox_outlined, color: theme.colorScheme.primary),
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
          )
        else
          ...filtered.map((s) {
            final tint = _statusTint(context, s.status);
            final time = s.scheduledStart == null
                ? '—'
                : timeFormat.format(s.scheduledStart!);

            final priority = s.priority <= 1
                ? 'Alta Prioridad'
                : (s.priority >= 3 ? 'Baja Prioridad' : 'Prioridad');
            final showPriority = s.priority <= 1;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  onTap: () => widget.onOpenService(s),
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_statusIcon(s.status), color: tint, size: 20),
                  ),
                  title: Text(
                    s.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_typeLabel(s.serviceType)} · ${s.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _inlineChip(
                              context,
                              icon: Icons.schedule,
                              text: time,
                            ),
                            _inlineChip(
                              context,
                              icon: Icons.person_outline,
                              text: 'Técnico: ${_techLabel(s)}',
                            ),
                            _inlineChip(
                              context,
                              icon: Icons.flag_outlined,
                              text: _statusLabel(s.status),
                            ),
                            if (showPriority)
                              _inlineChip(
                                context,
                                icon: Icons.priority_high,
                                text: priority,
                                tint: theme.colorScheme.error,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            );
          }),
      ],
    );
  }
}

Widget _inlineChip(
  BuildContext context, {
  required IconData icon,
  required String text,
  Color? tint,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final color = tint ?? cs.primary;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

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

class _ServiceDetailPanel extends StatefulWidget {
  final ServiceModel service;
  final Future<void> Function(String status) onChangeStatus;
  final Future<void> Function(DateTime start, DateTime end) onSchedule;
  final Future<void> Function() onCreateWarranty;
  final Future<void> Function(List<Map<String, String>> assignments) onAssign;
  final Future<void> Function(String stepId, bool done) onToggleStep;
  final Future<void> Function(String message) onAddNote;
  final Future<void> Function() onUploadEvidence;

  const _ServiceDetailPanel({
    required this.service,
    required this.onChangeStatus,
    required this.onSchedule,
    required this.onCreateWarranty,
    required this.onAssign,
    required this.onToggleStep,
    required this.onAddNote,
    required this.onUploadEvidence,
  });

  @override
  State<_ServiceDetailPanel> createState() => _ServiceDetailPanelState();
}

class _ServiceDetailPanelState extends State<_ServiceDetailPanel> {
  final _noteCtrl = TextEditingController();
  final _techCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    _techCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final nextStatuses = const [
      'survey',
      'scheduled',
      'in_progress',
      'completed',
      'warranty',
      'closed',
      'cancelled',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(service.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${service.customerName} · ${service.customerPhone}'),
        Text(
          '${service.serviceType} · ${service.category} · P${service.priority}',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DropdownButton<String>(
              value: service.status,
              items: nextStatuses
                  .map(
                    (status) =>
                        DropdownMenuItem(value: status, child: Text(status)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                widget.onChangeStatus(value);
              },
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                  initialDateRange: DateTimeRange(
                    start: service.scheduledStart ?? DateTime.now(),
                    end:
                        service.scheduledEnd ??
                        DateTime.now().add(const Duration(hours: 2)),
                  ),
                );
                if (picked == null) return;
                await widget.onSchedule(
                  DateTime(
                    picked.start.year,
                    picked.start.month,
                    picked.start.day,
                    8,
                  ),
                  DateTime(
                    picked.end.year,
                    picked.end.month,
                    picked.end.day,
                    18,
                  ),
                );
              },
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Agendar/Reagendar'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final ids = await _askTechIds(context);
                if (ids == null || ids.isEmpty) return;
                await widget.onAssign(
                  ids
                      .map(
                        (id) => <String, String>{
                          'userId': id,
                          'role': 'assistant',
                        },
                      )
                      .toList(),
                );
              },
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Asignar técnicos'),
            ),
            if (service.status == 'completed' || service.status == 'closed')
              FilledButton.icon(
                onPressed: widget.onCreateWarranty,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Crear garantía'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => widget.onAddNote('Llegué al sitio'),
              child: const Text('Llegué al sitio'),
            ),
            OutlinedButton(
              onPressed: () => widget.onAddNote('Inicié trabajo'),
              child: const Text('Inicié'),
            ),
            OutlinedButton(
              onPressed: () => widget.onAddNote('Finalicé trabajo'),
              child: const Text('Finalicé'),
            ),
            OutlinedButton(
              onPressed: () async {
                final reason = await _askReason(context);
                if (reason == null || reason.trim().isEmpty) return;
                await widget.onAddNote('Pendiente por: ${reason.trim()}');
              },
              child: const Text('Pendiente por X'),
            ),
            FilledButton.icon(
              onPressed: widget.onUploadEvidence,
              icon: const Icon(Icons.attach_file),
              label: const Text('Subir evidencia'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('Datos del cliente'),
        Text(
          service.customerAddress.isEmpty
              ? 'Sin dirección'
              : service.customerAddress,
        ),
        const SizedBox(height: 10),
        _sectionTitle('Checklist'),
        ...service.steps.map(
          (step) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(step.stepLabel),
            subtitle: step.doneAt == null
                ? null
                : Text('Completado ${dateFormat.format(step.doneAt!)}'),
            value: step.isDone,
            onChanged: (value) {
              if (value == null) return;
              widget.onToggleStep(step.id, value);
            },
          ),
        ),
        const SizedBox(height: 10),
        _sectionTitle('Evidencias'),
        if (service.files.isEmpty)
          const Text('Sin evidencias todavía')
        else
          ...service.files.map(
            (file) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(file.fileType),
              subtitle: Text(file.fileUrl),
            ),
          ),
        const SizedBox(height: 10),
        _sectionTitle('Historial'),
        if (service.updates.isEmpty)
          const Text('Sin movimientos')
        else
          ...service.updates
              .take(8)
              .map(
                (update) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    update.message.isEmpty ? update.type : update.message,
                  ),
                  subtitle: Text(
                    '${update.changedBy} · ${update.createdAt == null ? '-' : dateFormat.format(update.createdAt!)}',
                  ),
                ),
              ),
        const SizedBox(height: 10),
        _sectionTitle('Notas internas'),
        TextField(
          controller: _noteCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Escribe una nota interna...',
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
    );
  }

  Future<List<String>?> _askTechIds(BuildContext context) async {
    _techCtrl.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Asignar técnicos'),
        content: TextField(
          controller: _techCtrl,
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
    final value = _techCtrl.text.trim();
    if (value.isEmpty) return null;
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
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
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
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
                      _pill(
                        context,
                        'Último',
                        (_lastUpdateAt(service) ?? service.completedAt) == null
                            ? '—'
                            : df.format(
                                _lastUpdateAt(service) ?? service.completedAt!,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    service.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Historial de proceso',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
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
                                      style:
                                          TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: updates.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
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
            final haystack =
                '${s.customerName} ${s.customerPhone} ${s.title}'.toLowerCase();
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
                    TextButton(onPressed: _load, child: const Text('Reintentar')),
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
                    Icon(Icons.inbox_outlined, color: theme.colorScheme.primary),
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
                    label: 'Reserva',
                    icon: Icons.bookmark_add_outlined,
                    kind: 'reserva',
                  ),
                  _quickCreateButton(
                    context,
                    label: 'Levantamiento',
                    icon: Icons.fact_check_outlined,
                    kind: 'levantamiento',
                  ),
                  _quickCreateButton(
                    context,
                    label: 'Servicio',
                    icon: Icons.build_circle_outlined,
                    kind: 'servicio',
                  ),
                  _quickCreateButton(
                    context,
                    label: 'Garantía',
                    icon: Icons.verified_outlined,
                    kind: 'garantia',
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
    final lower = kind.trim().toLowerCase();
    final title = lower == 'reserva'
        ? 'Registrar reserva'
        : lower == 'levantamiento'
        ? 'Registrar levantamiento'
        : lower == 'servicio'
        ? 'Registrar servicio'
        : 'Registrar garantía';
    final submitLabel = lower == 'reserva'
        ? 'Guardar reserva'
        : lower == 'levantamiento'
        ? 'Guardar levantamiento'
        : lower == 'servicio'
        ? 'Guardar servicio'
        : 'Guardar garantía';

    final initialServiceType = lower == 'garantia'
        ? 'warranty'
        : 'installation';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
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
                const Divider(height: 1),
                Expanded(
                  child: _CreateReservationTab(
                    onCreate: (draft) async {
                      final ok = await onCreateFromAgenda(draft, lower);
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
  final double? quotedAmount;
  final double? depositAmount;
  final PlatformFile? referencePhoto;

  _CreateServiceDraft({
    required this.customerId,
    required this.serviceType,
    required this.category,
    required this.priority,
    required this.reservationAt,
    required this.title,
    required this.description,
    this.addressSnapshot,
    this.quotedAmount,
    this.depositAmount,
    this.referencePhoto,
  });
}

class _CreateReservationTab extends ConsumerStatefulWidget {
  final Future<void> Function(_CreateServiceDraft draft) onCreate;
  final String submitLabel;
  final String initialServiceType;
  final bool showServiceTypeField;

  const _CreateReservationTab({
    super.key,
    required this.onCreate,
    this.submitLabel = 'Guardar reserva',
    this.initialServiceType = 'installation',
    this.showServiceTypeField = true,
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

  late String _serviceType;
  late String _category;
  late int _priority;
  String? _customerId;
  String? _customerName;
  String? _customerPhone;
  DateTime? _reservationAt;
  bool _checkingCotizaciones = false;
  bool _hasCotizaciones = false;
  CotizacionModel? _selectedCotizacion;
  LatLng? _gpsPoint;
  PlatformFile? _referencePhoto;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _serviceType = widget.initialServiceType;
    _category = 'cameras';
    _priority = 1;
  }

  @override
  void dispose() {
    _searchClientCtrl.dispose();
    _reservationDateCtrl.dispose();
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _gpsCtrl.dispose();
    _quotedCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
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

    if (parsed == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pude detectar lat/lng en el texto')),
      );
    }
  }

  Future<void> _openGpsInMaps() async {
    final point = _gpsPoint ?? parseLatLngFromText(_gpsCtrl.text);
    if (point == null) return;
    final url = Uri.parse(buildGoogleMapsSearchUrl(point));
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String? _buildAddressSnapshot() {
    final address = _addressCtrl.text.trim();
    final point = _gpsPoint ?? parseLatLngFromText(_gpsCtrl.text);

    final hasAddress = address.isNotEmpty;
    final hasPoint = point != null;

    if (!hasAddress && !hasPoint) return null;
    if (!hasPoint) return address;

    final gpsLine = 'GPS: ${formatLatLng(point!)}';
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

        String money(double value) =>
            NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

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
                                      final picked = await _openCotizacionPickerDialog();
                                      if (!mounted || picked == null) return;
                                      setState(() {
                                        _selectedCotizacion = picked;
                                        _quotedCtrl.text = picked.total.toStringAsFixed(2);
                                      });
                                    },
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Seleccionar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await context.push(Routes.cotizaciones);
                                if (!mounted) return;
                                await _checkCotizacionesForSelectedClient();
                                final picked =
                                    await _openCotizacionPickerDialog();
                                if (!mounted || picked == null) return;
                                setState(() {
                                  _selectedCotizacion = picked;
                                  _quotedCtrl.text =
                                      picked.total.toStringAsFixed(2);
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
                  labelText: 'Fecha y hora de reserva',
                  suffixIcon: Icon(Icons.schedule_outlined),
                ),
                onTap: _pickReservationDate,
                validator: (_) => _reservationAt == null ? 'Requerido' : null,
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
                    DropdownMenuItem(value: 'pos', child: Text('Punto de ventas')),
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
                            DropdownMenuItem(value: 'pos', child: Text('Punto de ventas')),
                          ],
                          onChanged: (value) {
                            if (value != null)
                              setState(() => _category = value);
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
                      DropdownMenuItem(value: 'pos', child: Text('Punto de ventas')),
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
                  if (value != null) setState(() => _priority = value);
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
                controller: _gpsCtrl,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Ubicación GPS (WhatsApp/Maps)',
                  helperText: _gpsPoint == null
                      ? 'Pega un link de Google Maps o "lat,lng"'
                      : 'Detectado: ${formatLatLng(_gpsPoint!)}',
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
                          tooltip: 'Abrir en Maps',
                          onPressed: _gpsPoint == null ? null : _openGpsInMaps,
                          icon: const Icon(Icons.near_me_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _gpsPoint = parseLatLngFromText(value));
                },
              ),
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
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Precio vendido',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _depositCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Precio vendido',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _depositCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
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

        String money(double value) =>
            NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(value);

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
                  Future.microtask(() => load(setDialogState));
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
                            onPressed:
                                loading ? null : () => load(setDialogState),
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
                                child:
                                    Text('No hay cotizaciones para mostrar'),
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
                                      DateFormat('dd/MM/yyyy HH:mm')
                                          .format(item.createdAt),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () =>
                                        Navigator.pop(context, item),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push(Routes.cotizaciones);
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
                  Future.microtask(() => runSearch(setDialogState));
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

    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final title = '${_serviceTypeLabel(_serviceType)} · ${_categoryLabel(_category)}';
      final note = _descriptionCtrl.text.trim();
      final description = note.isEmpty ? 'Sin nota' : note;

      await widget.onCreate(
        _CreateServiceDraft(
          customerId: _customerId!,
          serviceType: _serviceType,
          category: _category,
          priority: _priority,
          reservationAt: _reservationAt,
          title: title,
          description: description,
          addressSnapshot: _buildAddressSnapshot(),
          quotedAmount: double.tryParse(_quotedCtrl.text.trim()),
          depositAmount: double.tryParse(_depositCtrl.text.trim()),
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
