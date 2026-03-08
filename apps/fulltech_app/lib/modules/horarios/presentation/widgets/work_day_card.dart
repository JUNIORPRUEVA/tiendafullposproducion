import 'package:flutter/material.dart';

import '../../../../features/contabilidad/widgets/app_card.dart';
import '../../horarios_models.dart';
import 'work_avatar.dart';
import 'work_status_pill.dart';
import 'work_status_style.dart';

class WorkDayCard extends StatelessWidget {
  final WorkDayAssignment assignment;
  final VoidCallback? onTap;
  final bool showEmployee;

  const WorkDayCard({
    super.key,
    required this.assignment,
    this.onTap,
    this.showEmployee = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final style = workStatusStyleForAssignment(assignment, scheme);

    final timeLabel = (assignment.startMinute != null && assignment.endMinute != null)
        ? '${minutesToHm(assignment.startMinute)}–${minutesToHm(assignment.endMinute)}'
        : '—';

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Row(
          children: [
            if (showEmployee) ...[
              WorkAvatar(name: assignment.userName),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          showEmployee ? assignment.userName : weekdayLabelEs(assignment.weekday),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (assignment.manualOverride) ...[
                        Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                      ],
                      WorkStatusPill(style: style),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if ((assignment.role ?? '').trim().isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(
                          Icons.badge_outlined,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          assignment.role!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if ((assignment.note ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      assignment.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
