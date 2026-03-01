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
        case 'pending':
          return 'Pendiente';
        case 'confirmed':
          return 'Confirmado';
        case 'assigned':
          return 'Asignado';
        case 'in_progress':
          return 'En proceso';
        case 'finalized':
          return 'Finalizado';
        case 'cancelled':
          return 'Cancelado';
        case 'rescheduled':
          return 'Reprogramado';

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
        case 'pending':
          return Icons.schedule_rounded;
        case 'confirmed':
          return Icons.check_circle_outline_rounded;
        case 'assigned':
          return Icons.person_pin_circle_outlined;
        case 'in_progress':
          return Icons.play_circle_outline_rounded;
        case 'finalized':
          return Icons.verified_outlined;
        case 'cancelled':
          return Icons.cancel_outlined;
        case 'rescheduled':
          return Icons.event_repeat_rounded;

        default:
          return Icons.circle_rounded;
      }
    }

    Color tint(String raw) {
      switch (raw) {
        case 'pending':
          return scheme.error;
        case 'confirmed':
          return scheme.primary;
        case 'assigned':
          return scheme.secondary;
        case 'in_progress':
          return scheme.tertiary;
        case 'finalized':
          return scheme.primary;
        case 'cancelled':
          return scheme.error;
        case 'rescheduled':
          return scheme.secondary;

        // Back-compat
        case 'scheduled':
          return scheme.primary;
        case 'in_progress':
          return scheme.tertiary;
        case 'completed':
        case 'closed':
          return scheme.primary;
        case 'cancelled':
          return scheme.error;

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
