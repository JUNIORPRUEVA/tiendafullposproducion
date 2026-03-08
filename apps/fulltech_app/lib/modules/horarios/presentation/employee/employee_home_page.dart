import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/error_banner.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_week_controller.dart';
import '../../horarios_models.dart';
import '../widgets/metric_card.dart';
import '../widgets/section_header.dart';
import '../widgets/work_status_pill.dart';
import '../widgets/work_status_style.dart';

class WorkSchedulingEmployeeHomePage extends ConsumerWidget {
  final VoidCallback onOpenCalendar;

  const WorkSchedulingEmployeeHomePage({
    super.key,
    required this.onOpenCalendar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;

    final weekState = ref.watch(workSchedulingWeekControllerProvider);
    final week = weekState.week;

    final now = DateTime.now();
    final todayIso = dateOnly(now);

    WorkDayAssignment? today;
    if (week != null) {
      for (final a in week.days) {
        if (a.date == todayIso) {
          today = a;
          break;
        }
      }
    }

    String? nextDayOff;
    if (week != null) {
      for (final a in week.days) {
        if (a.date.compareTo(todayIso) >= 0 && a.status != 'WORK') {
          nextDayOff = a.date;
          break;
        }
      }
    }

    String? nextWorkDay;
    if (week != null) {
      for (final a in week.days) {
        if (a.date.compareTo(todayIso) >= 0 && a.status == 'WORK') {
          nextWorkDay = a.date;
          break;
        }
      }
    }

    final workDays = week == null
        ? 0
        : week.days.where((a) => a.status == 'WORK').length;
    final offDays = week == null
        ? 0
        : week.days.where((a) => a.status != 'WORK').length;

    final conflicts = week == null
        ? 0
        : week.days.where((a) => a.conflictFlags.isNotEmpty).length;

    final style = today == null
        ? WorkStatusStyle(
            status: WorkUiStatus.pending,
            label: 'Sin dato',
            icon: Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )
        : workStatusStyleForAssignment(today, Theme.of(context).colorScheme);

    final todayLabel = today == null
        ? 'No hay horario cargado para hoy.'
        : (today.status == 'WORK' ? 'Hoy trabajas' : 'Hoy estás libre');

    final timeLabel = today == null
        ? '—'
        : (today.startMinute != null && today.endMinute != null)
        ? '${minutesToHm(today.startMinute)}–${minutesToHm(today.endMinute)}'
        : '—';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(
          title: 'Hola, ${user?.nombreCompleto ?? 'Usuario'}',
          subtitle: 'Tu calendario laboral y días libres.',
          trailing: Icon(
            Icons.verified_user_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (weekState.error != null) ...[
          ErrorBanner(message: weekState.error!),
          const SizedBox(height: 12),
        ],
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      todayLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  WorkStatusPill(style: style, compact: false),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Horario: $timeLabel',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Próximo día libre: ${nextDayOff ?? '—'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onOpenCalendar,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Ver calendario completo'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final cross = wide ? 3 : 2;

            return GridView.count(
              crossAxisCount: cross,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: wide ? 2.9 : 2.3,
              children: [
                MetricCard(
                  label: 'Días de trabajo',
                  value: '$workDays',
                  icon: Icons.work_outline,
                  tint: Theme.of(context).colorScheme.primary,
                  caption: 'Semana actual',
                ),
                MetricCard(
                  label: 'Días libres',
                  value: '$offDays',
                  icon: Icons.beach_access_outlined,
                  tint: AppTheme.successColor,
                  caption: 'Semana actual',
                ),
                MetricCard(
                  label: 'Próximo día laboral',
                  value: nextWorkDay ?? '—',
                  icon: Icons.event_note_outlined,
                  tint: AppTheme.primaryColor,
                ),
                MetricCard(
                  label: 'Alertas',
                  value: '$conflicts',
                  icon: Icons.error_outline,
                  tint: AppTheme.warningColor,
                  caption: conflicts == 0 ? 'Todo OK' : 'Revisar detalle',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notificaciones',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.notifications_none_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Sin notificaciones por ahora.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
