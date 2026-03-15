import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';

import 'widgets/service_card_widget.dart';

enum TechOpsTab { hoy, pendientes, enProceso, finalizados }

class TechOperationsState {
  final bool loading;
  final String? error;
  final TechOpsTab tab;
  final List<ServiceModel> services;

  const TechOperationsState({
    this.loading = false,
    this.error,
    this.tab = TechOpsTab.hoy,
    this.services = const [],
  });

  TechOperationsState copyWith({
    bool? loading,
    String? error,
    TechOpsTab? tab,
    List<ServiceModel>? services,
    bool clearError = false,
  }) {
    return TechOperationsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      tab: tab ?? this.tab,
      services: services ?? this.services,
    );
  }
}

final techOperationsControllerProvider =
    StateNotifierProvider<TechOperationsController, TechOperationsState>((ref) {
      return TechOperationsController(ref);
    });

class TechOperationsController extends StateNotifier<TechOperationsState> {
  final Ref ref;

  TechOperationsController(this.ref) : super(const TechOperationsState()) {
    load();
  }

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);

    try {
      final repo = ref.read(operationsRepositoryProvider);

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      final basePage = await repo.listServices(page: 1, pageSize: 200);
      final todayPage = await repo.listServices(
        from: todayStart,
        to: todayEnd,
        page: 1,
        pageSize: 200,
      );

      final merged = <String, ServiceModel>{
        for (final s in basePage.items) s.id: s,
        for (final s in todayPage.items) s.id: s,
      };

      state = state.copyWith(loading: false, services: merged.values.toList());
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setTab(TechOpsTab tab) {
    if (state.tab == tab) return;
    state = state.copyWith(tab: tab);
  }
}

class OperacionesTecnicoScreen extends ConsumerWidget {
  const OperacionesTecnicoScreen({super.key});

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<ServiceModel> _filter(List<ServiceModel> all, TechOpsTab tab) {
    final now = DateTime.now();

    bool isAllowedPhase(ServiceModel service) {
      final phase = service.currentPhase.trim().toLowerCase();
      if (phase.isEmpty) return true;
      return phase != 'reserva' && phase != 'reserved';
    }

    bool isAllowedServiceType(ServiceModel service) {
      final type = techAllowedServiceTypeFrom(service);
      return type == TechAllowedServiceType.installation ||
          type == TechAllowedServiceType.maintenance ||
          type == TechAllowedServiceType.warranty ||
          type == TechAllowedServiceType.survey;
    }

    bool isFinalizado(ServiceStatus status) {
      return status == ServiceStatus.completed ||
          status == ServiceStatus.closed ||
          status == ServiceStatus.cancelled;
    }

    bool isPendiente(ServiceStatus status) {
      return status == ServiceStatus.reserved ||
          status == ServiceStatus.survey ||
          status == ServiceStatus.scheduled;
    }

    bool isEnProceso(ServiceStatus status) {
      return status == ServiceStatus.inProgress ||
          status == ServiceStatus.warranty;
    }

    final filtered = all
        .where((service) {
          // BUSINESS RULE: technicians must NOT see reservations.
          if (!isAllowedPhase(service)) return false;
          // Only show these types: Installation, Maintenance, Warranty, Survey.
          if (!isAllowedServiceType(service)) return false;

          final status = parseStatus(service.status);
          switch (tab) {
            case TechOpsTab.hoy:
              final start = service.scheduledStart;
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
      final aTime = a.scheduledStart?.millisecondsSinceEpoch ?? 0;
      final bTime = b.scheduledStart?.millisecondsSinceEpoch ?? 0;
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
                      final status = techStatusBadgeFrom(parseStatus(s.status));
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

                      return ServiceCardWidget(
                        service: s,
                        type: type,
                        status: status,
                        scheduledDateLabel: fmtDate(scheduled),
                        orderIdLabel: s.id.trim().isEmpty ? '—' : s.id.trim(),
                        assignedTechnicianLabel: assignedNames.isEmpty
                            ? '—'
                            : assignedNames.join(', '),
                        canManage: canManage,
                        onViewOrder: () {
                          final id = s.id.trim();
                          if (id.isEmpty) return;
                          context.go(Routes.operacionesTecnicoOrder(id));
                        },
                        onManageService: () {
                          final id = s.id.trim();
                          if (id.isEmpty) return;
                          context.go(Routes.operacionesTecnicoDetail(id));
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
