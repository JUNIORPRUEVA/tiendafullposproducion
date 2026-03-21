import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/routes.dart';
import '../../../core/widgets/app_drawer.dart';
import '../application/operations_controller.dart';
import '../operations_models.dart';
import '../presentation/operations_back_button.dart';
import 'garantia_screen.dart';
import 'levantamiento_screen.dart';
import 'technical_service_execution_screen.dart';

class TechnicalServicePhaseRouterScreen extends ConsumerWidget {
  final String serviceId;

  const TechnicalServicePhaseRouterScreen({super.key, required this.serviceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final asyncService = ref.watch(serviceProvider(serviceId));

    return asyncService.when(
      loading: () => Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        appBar: AppBar(
          leading: const OperationsBackButton(
            fallbackRoute: Routes.operacionesTecnico,
          ),
          title: const Text('Servicio'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        appBar: AppBar(
          leading: const OperationsBackButton(
            fallbackRoute: Routes.operacionesTecnico,
          ),
          title: const Text('Servicio'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No se pudo cargar el servicio',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(serviceProvider(serviceId)),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (service) {
        final phase = effectiveServicePhaseKey(service);
        if (phase == 'levantamiento') {
          return LevantamientoScreen(serviceId: serviceId);
        }
        if (phase == 'garantia') {
          return GarantiaScreen(serviceId: serviceId);
        }
        return TechnicalServiceExecutionScreen(serviceId: serviceId);
      },
    );
  }
}
