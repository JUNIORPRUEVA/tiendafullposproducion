import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/error_banner.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../horarios_models.dart';
import '../../application/work_scheduling_admin_controller.dart';
import '../../application/work_scheduling_week_controller.dart';
import '../widgets/metric_card.dart';
import '../widgets/section_header.dart';

class WorkSchedulingAdminHomePage extends ConsumerWidget {
  const WorkSchedulingAdminHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekState = ref.watch(workSchedulingWeekControllerProvider);
    final adminState = ref.watch(workSchedulingAdminControllerProvider);

    final now = DateTime.now();
    final todayIso = dateOnly(now);

    final week = weekState.week;
    final todayItems = week == null
        ? const <WorkDayAssignment>[]
        : week.days.where((a) => a.date == todayIso).toList(growable: false);

    final activeEmployees = adminState.employees
        .where((e) => !e.blocked && e.schedule.enabled)
        .length;

    final workingToday = todayItems.where((a) => a.status == 'WORK').length;
    final offToday = todayItems.where((a) => a.status != 'WORK').length;
    final conflicts = week == null
        ? 0
        : week.days.where((a) => a.conflictFlags.isNotEmpty).length;

    final manualChanges = week == null
        ? 0
        : week.days.where((a) => a.manualOverride).length;

    final shortageWarnings = week == null
        ? const <Map<String, dynamic>>[]
        : week.warnings
              .where((w) => (w['type'] ?? '').toString() == 'COVERAGE_SHORTAGE')
              .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'Resumen general',
          subtitle: 'Visión rápida de cobertura, conflictos y cambios.',
        ),
        const SizedBox(height: 12),
        if (adminState.error != null) ...[
          ErrorBanner(message: adminState.error!),
          const SizedBox(height: 12),
        ],
        if (weekState.error != null) ...[
          ErrorBanner(message: weekState.error!),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final cross = wide ? 3 : 2;

            final tiles = <Widget>[
              MetricCard(
                label: 'Empleados activos',
                value: '$activeEmployees',
                icon: Icons.people_alt_outlined,
                tint: AppTheme.primaryColor,
              ),
              MetricCard(
                label: 'Trabajando hoy',
                value: '$workingToday',
                icon: Icons.work_outline_rounded,
                tint: Theme.of(context).colorScheme.primary,
              ),
              MetricCard(
                label: 'Libres hoy',
                value: '$offToday',
                icon: Icons.beach_access_outlined,
                tint: AppTheme.successColor,
              ),
              MetricCard(
                label: 'Cambios manuales',
                value: '$manualChanges',
                icon: Icons.edit_note_rounded,
                tint: AppTheme.warningColor,
                caption: 'En la semana actual',
              ),
              MetricCard(
                label: 'Conflictos detectados',
                value: '$conflicts',
                icon: Icons.error_outline,
                tint: AppTheme.errorColor,
              ),
              MetricCard(
                label: 'Baja cobertura',
                value: '${shortageWarnings.length}',
                icon: Icons.warning_amber_rounded,
                tint: AppTheme.warningColor,
                caption: 'Alertas en la semana',
              ),
            ];

            return GridView.count(
              crossAxisCount: cross,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: wide ? 2.9 : 2.3,
              children: tiles,
            );
          },
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Próximos días con baja cobertura',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.trending_down_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (shortageWarnings.isEmpty)
                Text(
                  'Sin alertas de cobertura en esta semana.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...shortageWarnings.take(8).map((w) {
                  final role = (w['role'] ?? '').toString();
                  final date = (w['date'] ?? '').toString();
                  final weekday = (w['weekday'] as num?)?.toInt() ?? 0;
                  final missing = (w['missing'] as num?)?.toInt() ?? 0;
                  final min = (w['min_required'] as num?)?.toInt() ?? 0;
                  final working = (w['working'] as num?)?.toInt() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: AppTheme.warningColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$date ${weekdayLabelEs(weekday)} — $role: $working/$min (faltan $missing)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
