import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/error_banner.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../application/work_scheduling_month_controller.dart';
import '../../application/work_scheduling_week_controller.dart';
import '../../horarios_models.dart';
import '../widgets/section_header.dart';
import '../widgets/work_day_card.dart';
import '../widgets/work_month_calendar.dart';

enum _CalendarView { week, month }

class WorkSchedulingAdminCalendarPage extends ConsumerStatefulWidget {
  const WorkSchedulingAdminCalendarPage({super.key});

  @override
  ConsumerState<WorkSchedulingAdminCalendarPage> createState() =>
      _WorkSchedulingAdminCalendarPageState();
}

class _WorkSchedulingAdminCalendarPageState
    extends ConsumerState<WorkSchedulingAdminCalendarPage> {
  _CalendarView _view = _CalendarView.week;
  String? _roleFilter;

  @override
  Widget build(BuildContext context) {
    final weekState = ref.watch(workSchedulingWeekControllerProvider);
    final weekCtrl = ref.read(workSchedulingWeekControllerProvider.notifier);

    final monthState = ref.watch(workSchedulingMonthControllerProvider);
    final monthCtrl = ref.read(workSchedulingMonthControllerProvider.notifier);

    final weekStart = weekState.weekStart;
    final weekEnd = weekStart.add(const Duration(days: 6));

    final roles = <String>{};
    if (weekState.week != null) {
      for (final a in weekState.week!.days) {
        final role = (a.role ?? '').trim();
        if (role.isNotEmpty) roles.add(role);
      }
    }
    final rolesList = roles.toList()..sort();

    Iterable<WorkDayAssignment> applyRoleFilter(
      Iterable<WorkDayAssignment> items,
    ) {
      final role = _roleFilter;
      if (role == null || role.isEmpty) return items;
      return items.where((a) => (a.role ?? '') == role);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(
          title: 'Calendario',
          subtitle: 'Semana y mes con cobertura y cambios manuales.',
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
          child: Column(
            children: [
              Row(
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
                      onSelectionChanged: (v) {
                        setState(() => _view = v.first);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _roleFilter,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todos los roles'),
                        ),
                        ...rolesList.map(
                          (r) => DropdownMenuItem<String?>(
                            value: r,
                            child: Text(r),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _roleFilter = v),
                      decoration: const InputDecoration(
                        labelText: 'Rol',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
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
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_view == _CalendarView.week)
          _WeekView(
            weekStart: weekStart,
            weekEnd: weekEnd,
            weekState: weekState,
            weekCtrl: weekCtrl,
            filter: applyRoleFilter,
          )
        else
          _MonthView(
            monthState: monthState,
            monthCtrl: monthCtrl,
            filter: applyRoleFilter,
          ),
      ],
    );
  }
}

class _WeekView extends StatelessWidget {
  final DateTime weekStart;
  final DateTime weekEnd;
  final WorkSchedulingWeekState weekState;
  final WorkSchedulingWeekController weekCtrl;
  final Iterable<WorkDayAssignment> Function(Iterable<WorkDayAssignment>)
  filter;

  const _WeekView({
    required this.weekStart,
    required this.weekEnd,
    required this.weekState,
    required this.weekCtrl,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    final week = weekState.week;

    final weekDates = List.generate(
      7,
      (i) => dateOnly(weekStart.add(Duration(days: i))),
    );

    final byUser = <String, List<WorkDayAssignment>>{};
    if (week != null) {
      for (final a in week.days) {
        byUser.putIfAbsent(a.userId, () => []).add(a);
      }
    }

    Future<void> openManualSheet(WorkDayAssignment assignment) async {
      final reasonCtrl = TextEditingController(text: 'Ajuste manual');

      final otherDates = weekDates.where((d) => d != assignment.date).toList();
      String moveToDate = otherDates.isNotEmpty
          ? otherDates.first
          : assignment.date;

      final dayOffByUser = <String, List<String>>{};
      for (final entry in byUser.entries) {
        final offDates =
            entry.value
                .where((a) => a.status == 'DAY_OFF')
                .map((a) => a.date)
                .toSet()
                .toList()
              ..sort();
        if (offDates.isNotEmpty) dayOffByUser[entry.key] = offDates;
      }

      final swapUserIds =
          dayOffByUser.keys.where((id) => id != assignment.userId).toList()
            ..sort();

      String? swapUserId = swapUserIds.isNotEmpty ? swapUserIds.first : null;
      String? swapUserDayOffDate =
          (swapUserId != null &&
              (dayOffByUser[swapUserId]?.isNotEmpty ?? false))
          ? dayOffByUser[swapUserId]!.first
          : null;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final inset = MediaQuery.viewInsetsOf(ctx);
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 16 + inset.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cambios manuales',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${assignment.userName}\nDía libre actual: ${assignment.date}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Motivo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: moveToDate,
                      items: otherDates
                          .map(
                            (d) => DropdownMenuItem(value: d, child: Text(d)),
                          )
                          .toList(),
                      onChanged: (v) => setModalState(() {
                        moveToDate = v ?? moveToDate;
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Mover día libre a',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: 'Mover día libre',
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await weekCtrl.manualMoveDayOff(
                          userId: assignment.userId,
                          fromDate: assignment.date,
                          toDate: moveToDate,
                          reason: reasonCtrl.text.trim().isEmpty
                              ? 'Ajuste manual'
                              : reasonCtrl.text.trim(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (swapUserId != null && swapUserDayOffDate != null) ...[
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: swapUserId,
                        items: swapUserIds.map((id) {
                          final name = byUser[id]?.first.userName ?? id;
                          return DropdownMenuItem(value: id, child: Text(name));
                        }).toList(),
                        onChanged: (v) => setModalState(() {
                          swapUserId = v;
                          final dates = dayOffByUser[v] ?? const [];
                          swapUserDayOffDate = dates.isNotEmpty
                              ? dates.first
                              : null;
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Intercambiar con',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: swapUserDayOffDate,
                        items: (dayOffByUser[swapUserId] ?? const [])
                            .map(
                              (d) => DropdownMenuItem(value: d, child: Text(d)),
                            )
                            .toList(),
                        onChanged: (v) => setModalState(() {
                          swapUserDayOffDate = v;
                        }),
                        decoration: const InputDecoration(
                          labelText: 'Día libre del otro empleado',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      PrimaryButton(
                        label: 'Intercambiar días libres',
                        onPressed: () async {
                          final bId = swapUserId;
                          final bDate = swapUserDayOffDate;
                          if (bId == null || bDate == null) return;
                          Navigator.pop(ctx);
                          await weekCtrl.manualSwapDayOff(
                            userAId: assignment.userId,
                            userADayOffDate: assignment.date,
                            userBId: bId,
                            userBDayOffDate: bDate,
                            reason: reasonCtrl.text.trim().isNotEmpty
                                ? reasonCtrl.text.trim()
                                : 'Ajuste manual',
                          );
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      );

      reasonCtrl.dispose();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No hay horarios generados para esta semana.',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  'Genera la semana para asignar días libres y validar cobertura mínima.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Generar semana',
                  loading: weekState.loading,
                  onPressed: () => weekCtrl.generateWeek(mode: 'REPLACE'),
                ),
              ],
            ),
          )
        else ...[
          if (week.warnings.isNotEmpty)
            AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Validación',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...week.warnings.take(10).map((w) {
                    final type = (w['type'] ?? '').toString();
                    if (type == 'COVERAGE_SHORTAGE') {
                      final role = (w['role'] ?? '').toString();
                      final date = (w['date'] ?? '').toString();
                      final weekday = (w['weekday'] as num?)?.toInt() ?? 0;
                      final missing = (w['missing'] as num?)?.toInt() ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• $date ${weekdayLabelEs(weekday)} — $role: faltan $missing',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('• $type'),
                    );
                  }),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: weekState.loading
                      ? null
                      : () => weekCtrl.generateWeek(mode: 'KEEP_MANUAL'),
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Regenerar (mantener manual)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: weekState.loading
                      ? null
                      : () => weekCtrl.generateWeek(mode: 'REPLACE'),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Regenerar (reemplazar)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < 7; i++) ...[
            _DaySection(
              date: weekStart.add(Duration(days: i)),
              items: filter(
                week.days.where(
                  (a) => a.date == dateOnly(weekStart.add(Duration(days: i))),
                ),
              ).toList(growable: false),
              onAssignmentTap: (a) {
                if (a.status != 'DAY_OFF') return;
                openManualSheet(a);
              },
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _DaySection extends StatelessWidget {
  final DateTime date;
  final List<WorkDayAssignment> items;
  final void Function(WorkDayAssignment a)? onAssignmentTap;

  const _DaySection({
    required this.date,
    required this.items,
    this.onAssignmentTap,
  });

  @override
  Widget build(BuildContext context) {
    final iso = dateOnly(date);
    final weekday = weekdayLabelEs((date.weekday - 1) % 7);

    final sorted = items.toList()
      ..sort(
        (a, b) => a.userName.toLowerCase().compareTo(b.userName.toLowerCase()),
      );

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$weekday • $iso',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${sorted.length} asignaciones',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sorted.isEmpty)
            Text(
              'Sin asignaciones.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...sorted.map(
              (a) => WorkDayCard(
                assignment: a,
                showEmployee: true,
                onTap: onAssignmentTap == null
                    ? null
                    : () => onAssignmentTap!(a),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthView extends ConsumerWidget {
  final WorkSchedulingMonthState monthState;
  final WorkSchedulingMonthController monthCtrl;
  final Iterable<WorkDayAssignment> Function(Iterable<WorkDayAssignment>)
  filter;

  const _MonthView({
    required this.monthState,
    required this.monthCtrl,
    required this.filter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    Iterable<WorkDayAssignment> itemsForDate(String iso) {
      final items = monthState.byDateAndUser.entries
          .where((e) => e.key.startsWith('$iso|'))
          .map((e) => e.value);
      return filter(items);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        if (monthState.loading)
          AppCard(
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Cargando mes…',
                  style: TextStyle(color: scheme.onSurfaceVariant),
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
    final list = items.toList(growable: false)
      ..sort(
        (a, b) => a.userName.toLowerCase().compareTo(b.userName.toLowerCase()),
      );

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
                    'Sin asignaciones para este día.',
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
                          child: WorkDayCard(assignment: a, showEmployee: true),
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
