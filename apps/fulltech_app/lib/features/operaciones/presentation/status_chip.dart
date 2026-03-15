import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  final String status;
  final bool compact;

  const StatusChip({super.key, required this.status, this.compact = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final normalized = status.trim().toLowerCase();

    String label(String raw) {
      switch (raw) {
        // AdminOrderStatus
        case 'pendiente':
        case 'pending':
          return 'Pendiente';
        case 'confirmada':
        case 'confirmed':
          return 'Confirmada';
        case 'asignada':
        case 'assigned':
          return 'Asignado';
        case 'en_camino':
          return 'En camino';
        case 'en_proceso':
        case 'in_progress':
          return 'En proceso';
        case 'finalizada':
        case 'finalized':
          return 'Finalizado';
        case 'cerrada':
          return 'Cerrada';
        case 'cancelada':
        case 'cancelled':
          return 'Cancelado';
        case 'reagendada':
        case 'rescheduled':
          return 'Reagendada';

        // Back-compat: ServiceStatus
        case 'reserved':
          return 'Reserva';
        case 'survey':
          return 'Levantamiento';
        case 'scheduled':
          return 'Agendado';
        case 'completed':
          return 'Completado';
        case 'closed':
          return 'Cerrado';

        default:
          return raw.isEmpty ? '—' : raw;
      }
    }

    IconData icon(String raw) {
      switch (raw) {
        case 'pendiente':
        case 'pending':
          return Icons.schedule_rounded;
        case 'confirmada':
        case 'confirmed':
          return Icons.check_circle_outline_rounded;
        case 'asignada':
        case 'assigned':
          return Icons.person_pin_circle_outlined;
        case 'en_camino':
          return Icons.directions_car_outlined;
        case 'en_proceso':
        case 'in_progress':
          return Icons.play_circle_outline_rounded;
        case 'finalizada':
        case 'finalized':
          return Icons.verified_outlined;
        case 'cerrada':
          return Icons.lock_outline_rounded;
        case 'cancelada':
        case 'cancelled':
          return Icons.cancel_outlined;
        case 'reagendada':
        case 'rescheduled':
          return Icons.event_repeat_rounded;

        default:
          return Icons.circle_rounded;
      }
    }

    Color tint(String raw) {
      switch (raw) {
        case 'pendiente':
        case 'pending':
          return scheme.error;
        case 'confirmada':
        case 'confirmed':
          return scheme.primary;
        case 'asignada':
        case 'assigned':
          return scheme.secondary;
        case 'en_camino':
          return scheme.secondary;
        case 'en_proceso':
        case 'in_progress':
          return scheme.tertiary;
        case 'finalizada':
        case 'finalized':
          return scheme.primary;
        case 'cerrada':
          return scheme.primary;
        case 'cancelada':
        case 'cancelled':
          return scheme.error;
        case 'reagendada':
        case 'rescheduled':
          return scheme.secondary;

        // Back-compat
        case 'scheduled':
          return scheme.primary;
        case 'completed':
        case 'closed':
          return scheme.primary;

        default:
          return scheme.onSurface.withValues(alpha: 0.70);
      }
    }

    final t = tint(normalized);
    final text = label(normalized);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: t.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon(normalized), size: compact ? 14 : 16, color: t),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: t,
            ),
          ),
        ],
      ),
    );
  }
}
