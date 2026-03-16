import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import '../presentation/service_location_helpers.dart';

import 'widgets/service_card_widget.dart';

import 'application/tech_operations_controller.dart';

class OperacionesTecnicoScreen extends ConsumerWidget {
  const OperacionesTecnicoScreen({super.key});

  String _normalizeKey(String raw) {
    var v = raw.trim().toLowerCase();
    if (v.isEmpty) return '';
    v = v
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
    v = v.replaceAll(' ', '_').replaceAll('-', '_');
    return v;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<ServiceModel> _filter(List<ServiceModel> all, TechOpsTab tab) {
    final now = DateTime.now();

    bool isFinalizado(ServiceStatus status) {
      return status == ServiceStatus.completed ||
          status == ServiceStatus.closed ||
          status == ServiceStatus.cancelled;
    }

    bool isPendiente(ServiceStatus status) {
      return status == ServiceStatus.survey ||
          status == ServiceStatus.scheduled;
    }

    bool isEnProceso(ServiceStatus status) {
      return status == ServiceStatus.inProgress ||
          status == ServiceStatus.warranty;
    }

    final filtered = all
        .where((service) {
          final rawStatus = service.orderState.trim().isEmpty
              ? service.status
              : service.orderState;
          final status = parseStatus(rawStatus);

          // BUSINESS RULE: technicians must NOT see reservations.
          // Avoid hiding everything when backend omits fields and the model
          // defaults to reserva/pending.
          final hasScheduling =
              service.scheduledStart != null || service.scheduledEnd != null;
          final hasTechnician = (service.technicianId ?? '').trim().isNotEmpty;
          final hasAssignments = service.assignments.isNotEmpty;
          final hasCompletion = service.completedAt != null;
          final orderTypeKey = _normalizeKey(service.orderType);
          final phaseKey = _normalizeKey(service.currentPhase);
          final hasReservationHint =
              orderTypeKey.contains('reserva') ||
              orderTypeKey.contains('reserv') ||
              phaseKey.contains('reserva') ||
              phaseKey.contains('reserv') ||
              status == ServiceStatus.reserved;

          final looksLikeReservation =
              hasReservationHint &&
              !hasScheduling &&
              !hasTechnician &&
              !hasAssignments &&
              !hasCompletion;
          if (looksLikeReservation) return false;

          switch (tab) {
            case TechOpsTab.hoy:
              final start = service.scheduledStart ?? service.scheduledEnd;
              if (start == null) return false;
              return _isSameDay(start.toLocal(), now);
            case TechOpsTab.pendientes:
              return isPendiente(status);
            case TechOpsTab.enProceso:
              return isEnProceso(status);
            case TechOpsTab.finalizados:
              return isFinalizado(status);
          }
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      final aTime =
          (a.scheduledStart ?? a.scheduledEnd)?.millisecondsSinceEpoch ?? 0;
      final bTime =
          (b.scheduledStart ?? b.scheduledEnd)?.millisecondsSinceEpoch ?? 0;
      return aTime.compareTo(bTime);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(techOperationsControllerProvider);
    final ctrl = ref.read(techOperationsControllerProvider.notifier);
    final user = ref.watch(authStateProvider).user;

    final tabItems = [
      (TechOpsTab.hoy, 'Hoy'),
      (TechOpsTab.pendientes, 'Pendientes'),
      (TechOpsTab.enProceso, 'En proceso'),
      (TechOpsTab.finalizados, 'Finalizados'),
    ];

    final services = _filter(st.services, st.tab);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis servicios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: st.loading ? null : () => ctrl.load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                for (final item in tabItems) ...[
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: st.tab == item.$1,
                    onSelected: (_) => ctrl.setTab(item.$1),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (st.loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: st.error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(st.error!, textAlign: TextAlign.center),
                    ),
                  )
                : services.isEmpty
                ? const Center(child: Text('No hay servicios'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                    itemCount: services.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final s = services[index];

                      String fmtDate(DateTime? dt) {
                        if (dt == null) return '—';
                        final v = dt.toLocal();
                        final d = v.day.toString().padLeft(2, '0');
                        final m = v.month.toString().padLeft(2, '0');
                        final y = v.year.toString();
                        return '$d/$m/$y';
                      }

                      final type = techAllowedServiceTypeFrom(s);
                      final rawStatus = s.orderState.trim().isEmpty
                          ? s.status
                          : s.orderState;
                      final status = techStatusBadgeFrom(
                        parseStatus(rawStatus),
                      );
                      final scheduled = s.scheduledStart ?? s.scheduledEnd;
                      final assignedNames = s.assignments
                          .map((a) => a.userName.trim())
                          .where((n) => n.isNotEmpty)
                          .toList();

                      final perms = OperationsPermissions(
                        user: user,
                        service: s,
                      );
                      final canManage =
                          user != null &&
                          (perms.isAdminLike || perms.canOperate);

                      final location = buildServiceLocationInfo(
                        addressOrText: s.customerAddress,
                      );

                      VoidCallback? onOpenLocation;
                      if (location.canOpenMaps) {
                        onOpenLocation = () async {
                          final uri = location.mapsUri;
                          if (uri == null) return;
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        };
                      }

                      final id = s.id.trim();
                      final orderLabel = s.orderLabel.trim();
                      return Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: ServiceCardWidget(
                            service: s,
                            type: type,
                            status: status,
                            scheduledDateLabel: fmtDate(scheduled),
                            orderIdLabel: orderLabel.isEmpty ? '—' : orderLabel,
                            assignedTechnicianLabel: assignedNames.isEmpty
                                ? '—'
                                : assignedNames.join(', '),
                            canManage: canManage,
                            onOpenDetails: () {
                              if (id.isEmpty) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!context.mounted) return;
                                context.push(Routes.operacionesTecnicoOrder(id));
                              });
                            },
                            onManageService: () {
                              if (id.isEmpty) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!context.mounted) return;
                                context.push(Routes.operacionesTecnicoDetail(id));
                              });
                            },
                            onOpenLocation: onOpenLocation,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
