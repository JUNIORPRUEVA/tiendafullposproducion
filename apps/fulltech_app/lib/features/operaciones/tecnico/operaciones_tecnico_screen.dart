import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/app_drawer.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import '../presentation/service_location_helpers.dart';

import 'application/tech_operations_controller.dart';
import 'presentation/tech_operations_filters.dart';
import 'widgets/compact_filter_bar.dart';
import 'widgets/compact_header_widget.dart';
import 'widgets/compact_order_card.dart';
import 'widgets/orders_list_section.dart';

class OperacionesTecnicoScreen extends ConsumerWidget {
  final List<ServiceModel>? servicesOverride;

  const OperacionesTecnicoScreen({super.key, this.servicesOverride});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(techOperationsControllerProvider);
    final ctrl = ref.read(techOperationsControllerProvider.notifier);
    final user = ref.watch(authStateProvider).user;
    final filterState = ref.watch(techOperationsFilterProvider);
    final filterCtrl = ref.read(techOperationsFilterProvider.notifier);
    final services = servicesOverride ?? st.services;
    final filteredServices = filterTechOrders(services, filterState);
    final summary = summarizeTechOrders(services);
    final statusCounts = buildStatusCounts(services);
    final phaseCounts = buildPhaseCounts(services);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFD),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: Builder(
        builder: (scaffoldContext) => SafeArea(
          bottom: false,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF9FBFF),
                  Color(0xFFEAF3FF),
                  Color(0xFFF4FBF7),
                ],
              ),
            ),
            child: Column(
              children: [
                if (st.loading && services.isNotEmpty)
                  const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: CompactHeaderWidget(
                      summary: summary,
                      visibleCount: filteredServices.length,
                      onOpenDrawer: () =>
                          Scaffold.of(scaffoldContext).openDrawer(),
                      onRefresh: servicesOverride == null
                          ? () => ctrl.refresh()
                          : null,
                      isRefreshing: st.loading,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: CompactFilterBar(
                      state: filterState,
                      statusCounts: statusCounts,
                      phaseCounts: phaseCounts,
                      onToggleStatus: filterCtrl.toggleStatus,
                      onTogglePhase: filterCtrl.togglePhase,
                      onClear: filterCtrl.clear,
                    ),
                  ),
                ),
                Expanded(
                  child: OrdersListSection(
                    loading: st.loading,
                    error: st.error,
                    services: filteredServices,
                    onRefresh: servicesOverride == null
                        ? () => ctrl.refresh()
                        : null,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    itemSpacing: 5,
                    itemBuilder: (context, service) {
                      final perms = OperationsPermissions(
                        user: user,
                        service: service,
                      );
                      final canManage =
                          user != null &&
                          (perms.isAdminLike || perms.canOperate);

                      final location = buildServiceLocationInfo(
                        addressOrText: service.customerAddress,
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

                      final serviceId = service.id.trim();
                      return CompactOrderCard(
                        service: service,
                        locationLabel: location.label == 'Sin ubicación'
                            ? null
                            : location.label,
                        canManage: canManage,
                        onOpenDetails: () {
                          if (serviceId.isEmpty) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            context.push(
                              Routes.operacionesTecnicoOrder(serviceId),
                            );
                          });
                        },
                        onManageService: () {
                          if (serviceId.isEmpty) return;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            context.push(
                              Routes.operacionesTecnicoDetail(serviceId),
                            );
                          });
                        },
                        onOpenLocation: onOpenLocation,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
