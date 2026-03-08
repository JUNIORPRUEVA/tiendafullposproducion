import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../../../core/widgets/error_banner.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_month_controller.dart';
import '../../application/work_scheduling_week_controller.dart';
import '../../horarios_models.dart';
import '../widgets/section_header.dart';
import '../widgets/work_day_card.dart';
import '../widgets/work_month_calendar.dart';

enum _CalendarView { week, month }

class WorkSchedulingEmployeeCalendarPage extends ConsumerStatefulWidget {
  const WorkSchedulingEmployeeCalendarPage({super.key});

  @override
  ConsumerState<WorkSchedulingEmployeeCalendarPage> createState() =>
      _WorkSchedulingEmployeeCalendarPageState();
}

class _WorkSchedulingEmployeeCalendarPageState
    extends ConsumerState<WorkSchedulingEmployeeCalendarPage> {
  _CalendarView _view = _CalendarView.week;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final userId = user?.id;

    final weekState = ref.watch(workSchedulingWeekControllerProvider);
    final weekCtrl = ref.read(workSchedulingWeekControllerProvider.notifier);

    final monthState = ref.watch(workSchedulingMonthControllerProvider);
    final monthCtrl = ref.read(workSchedulingMonthControllerProvider.notifier);

    final weekStart = weekState.weekStart;
    final weekEnd = weekStart.add(const Duration(days: 6));

    Iterable<WorkDayAssignment> filterMine(Iterable<WorkDayAssignment> items) {
      if (userId == null) return const [];
      return items.where((a) => a.userId == userId);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'Mi calendario',
          subtitle: 'Semana y mes de tu horario.',
        ),
        const SizedBox(height: 12),
        if (weekState.error != null) ...[
          ErrorBanner(message: weekState.error!),
          const SizedBox(height: 10),
        ],
        if (monthState.error != null) ...[
          ErrorBanner(message: monthState.error!),
          const SizedBox(height: 10),
        ],
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_CalendarView>(
                  segments: const [
                    ButtonSegment(
                      value: _CalendarView.week,
                      label: Text('Semana'),
                      icon: Icon(Icons.view_week_outlined),
                    ),
                    ButtonSegment(
                      value: _CalendarView.month,
                      label: Text('Mes'),
                      icon: Icon(Icons.calendar_month_outlined),
                    ),
                  ],
                  selected: {_view},
                  onSelectionChanged: (v) => setState(() => _view = v.first),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: weekState.loading ? null : weekCtrl.load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_view == _CalendarView.week)
          _WeekMine(
            weekStart: weekStart,
            weekEnd: weekEnd,
            weekState: weekState,
            weekCtrl: weekCtrl,
            filter: filterMine,
          )
        else
          _MonthMine(
            monthState: monthState,
            monthCtrl: monthCtrl,
            filter: filterMine,
          ),
      ],
    );
  }
}

class _WeekMine extends StatelessWidget {
  final DateTime weekStart;
  final DateTime weekEnd;
  final WorkSchedulingWeekState weekState;
  final WorkSchedulingWeekController weekCtrl;
  final Iterable<WorkDayAssignment> Function(Iterable<WorkDayAssignment>)
  filter;

  const _WeekMine({
    required this.weekStart,
    required this.weekEnd,
    required this.weekState,
    required this.weekCtrl,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final week = weekState.week;

    return Column(
      children: [
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Semana anterior',
                onPressed: weekState.loading ? null : weekCtrl.prevWeek,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${dateOnly(weekStart)} → ${dateOnly(weekEnd)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Semana siguiente',
                onPressed: weekState.loading ? null : weekCtrl.nextWeek,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (week == null)
          AppCard(
            child: Text(
              'Aún no hay horario para esta semana.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Semana',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                ...filter(week.days)
                    .toList(growable: false)
                    .map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: WorkDayCard(assignment: a, showEmployee: false),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthMine extends ConsumerWidget {
  final WorkSchedulingMonthState monthState;
  final WorkSchedulingMonthController monthCtrl;
  final Iterable<WorkDayAssignment> Function(Iterable<WorkDayAssignment>)
  filter;

  const _MonthMine({
    required this.monthState,
    required this.monthCtrl,
    required this.filter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Iterable<WorkDayAssignment> itemsForDate(String iso) {
      final items = monthState.byDateAndUser.entries
          .where((e) => e.key.startsWith('$iso|'))
          .map((e) => e.value);
      return filter(items);
    }

    return Column(
      children: [
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                onPressed: monthState.loading ? null : monthCtrl.prevMonth,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${monthState.month.year}-${monthState.month.month.toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: monthState.loading ? null : monthCtrl.nextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        WorkMonthCalendar(
          month: monthState.month,
          assignmentsForDate: itemsForDate,
          onDayTap: (iso) => _openDayDetail(context, iso, itemsForDate(iso)),
        ),
      ],
    );
  }

  Future<void> _openDayDetail(
    BuildContext context,
    String iso,
    Iterable<WorkDayAssignment> items,
  ) async {
    final list = items.toList(growable: false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detalle del día • $iso',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  Text(
                    'Sin asignación para este día.',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final a = list[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: WorkDayCard(
                            assignment: a,
                            showEmployee: false,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
