import 'package:flutter/material.dart';

import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../horarios_models.dart';

class WorkMonthCalendar extends StatelessWidget {
  final DateTime month;
  final Iterable<WorkDayAssignment> Function(String dateIso) assignmentsForDate;
  final void Function(String dateIso)? onDayTap;

  const WorkMonthCalendar({
    super.key,
    required this.month,
    required this.assignmentsForDate,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);

    final gridStart = _startOfWeekMonday(monthStart);
    final gridEnd = _startOfWeekMonday(monthEnd).add(const Duration(days: 6));

    final days = <DateTime>[];
    for (
      var d = gridStart;
      !d.isAfter(gridEnd);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(d);
    }

    String headerLabel(DateTime m) {
      const monthsEs = [
        'Enero',
        'Febrero',
        'Marzo',
        'Abril',
        'Mayo',
        'Junio',
        'Julio',
        'Agosto',
        'Septiembre',
        'Octubre',
        'Noviembre',
        'Diciembre',
      ];
      return '${monthsEs[m.month - 1]} ${m.year}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  headerLabel(month),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.calendar_month_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _WeekdayHeader(),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1.05,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, i) {
            final d = days[i];
            final inMonth = d.month == month.month;
            final iso = dateOnly(d);
            final items = assignmentsForDate(iso).toList(growable: false);

            final hasConflict = items.any((e) => e.conflictFlags.isNotEmpty);

            final workCount = items.where((e) => e.status == 'WORK').length;
            final offCount = items.where((e) => e.status != 'WORK').length;

            final border = hasConflict
                ? scheme.error.withValues(alpha: 0.65)
                : scheme.outlineVariant.withValues(alpha: 0.60);

            final bg = inMonth
                ? scheme.surface
                : scheme.surfaceContainerHighest.withValues(alpha: 0.65);

            return InkWell(
              onTap: onDayTap == null ? null : () => onDayTap!(iso),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${d.day}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: inMonth
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (hasConflict)
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: scheme.error,
                          ),
                      ],
                    ),
                    const Spacer(),
                    if (items.isEmpty)
                      Text(
                        '—',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Row(
                        children: [
                          _Dot(color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            '$workCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _Dot(color: scheme.tertiary),
                          const SizedBox(width: 6),
                          Text(
                            '$offCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _LegendDot(color: scheme.primary, label: 'Trabajo'),
            const SizedBox(width: 12),
            _LegendDot(color: scheme.tertiary, label: 'Libre/Permiso'),
          ],
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Row(
      children: [
        for (final l in labels)
          Expanded(
            child: Center(
              child: Text(
                l,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

DateTime _startOfWeekMonday(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final weekday = d.weekday;
  final delta = weekday - DateTime.monday;
  return d.subtract(Duration(days: delta));
}
