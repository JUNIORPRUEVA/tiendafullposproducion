import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../horarios_models.dart';

enum WorkUiStatus {
  work,
  dayOff,
  exception,
  conflict,
  pending,
  approved,
  rejected,
}

class WorkStatusStyle {
  final WorkUiStatus status;
  final String label;
  final IconData icon;
  final Color color;

  const WorkStatusStyle({
    required this.status,
    required this.label,
    required this.icon,
    required this.color,
  });

  Color bg(ColorScheme scheme) =>
      Color.alphaBlend(color.withValues(alpha: 0.10), scheme.surface);

  Color border(ColorScheme scheme) =>
      Color.alphaBlend(color.withValues(alpha: 0.40), scheme.outlineVariant);
}

WorkStatusStyle workStatusStyleForAssignment(
  WorkDayAssignment assignment,
  ColorScheme scheme,
) {
  if (assignment.conflictFlags.isNotEmpty) {
    return const WorkStatusStyle(
      status: WorkUiStatus.conflict,
      label: 'Conflicto',
      icon: Icons.error_outline_rounded,
      color: AppTheme.errorColor,
    );
  }

  switch (assignment.status.trim().toUpperCase()) {
    case 'DAY_OFF':
      return const WorkStatusStyle(
        status: WorkUiStatus.dayOff,
        label: 'Libre',
        icon: Icons.beach_access_outlined,
        color: AppTheme.successColor,
      );
    case 'EXCEPTION_OFF':
      return const WorkStatusStyle(
        status: WorkUiStatus.exception,
        label: 'Permiso',
        icon: Icons.event_busy_outlined,
        color: AppTheme.warningColor,
      );
    case 'WORK':
    default:
      return WorkStatusStyle(
        status: WorkUiStatus.work,
        label: 'Trabajo',
        icon: Icons.work_outline_rounded,
        color: scheme.primary,
      );
  }
}

WorkStatusStyle workStatusStyleForRequestState(String raw, ColorScheme scheme) {
  final v = raw.trim().toLowerCase();
  switch (v) {
    case 'pending':
      return const WorkStatusStyle(
        status: WorkUiStatus.pending,
        label: 'Pendiente',
        icon: Icons.schedule_rounded,
        color: AppTheme.warningColor,
      );
    case 'approved':
      return const WorkStatusStyle(
        status: WorkUiStatus.approved,
        label: 'Aprobada',
        icon: Icons.verified_rounded,
        color: AppTheme.successColor,
      );
    case 'rejected':
      return const WorkStatusStyle(
        status: WorkUiStatus.rejected,
        label: 'Rechazada',
        icon: Icons.cancel_outlined,
        color: AppTheme.errorColor,
      );
    default:
      return WorkStatusStyle(
        status: WorkUiStatus.pending,
        label: raw.trim().isEmpty ? '—' : raw,
        icon: Icons.info_outline,
        color: scheme.onSurfaceVariant,
      );
  }
}
