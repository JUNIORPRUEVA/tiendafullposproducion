import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/error_banner.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_admin_controller.dart';
import '../widgets/section_header.dart';

class WorkSchedulingAdminHistoryPage extends ConsumerWidget {
  const WorkSchedulingAdminHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workSchedulingAdminControllerProvider);
    final controller = ref.read(workSchedulingAdminControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(
          title: 'Historial',
          subtitle: 'Auditoría y reportes del módulo de horarios.',
          trailing: FilledButton.icon(
            onPressed: state.loading ? null : controller.loadAuditAndReports,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Cargar'),
          ),
        ),
        const SizedBox(height: 12),
        if (state.error != null) ...[
          ErrorBanner(message: state.error!),
          const SizedBox(height: 10),
        ],
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Actividad reciente',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              if (state.audit.isEmpty)
                Text(
                  'Sin auditoría en el rango.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...state.audit
                    .take(40)
                    .map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${a.createdAt.toIso8601String()}\n${a.action} • ${a.actorName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reportes (raw)',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'Cambios por empleado:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              if (state.reportMostChanges.isEmpty)
                const Text('—')
              else
                ...state.reportMostChanges.take(15).map((r) => Text('• $r')),
              const SizedBox(height: 10),
              Text(
                'Baja cobertura:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              if (state.reportLowCoverage.isEmpty)
                const Text('—')
              else
                ...state.reportLowCoverage.take(15).map((r) => Text('• $r')),
            ],
          ),
        ),
      ],
    );
  }
}
