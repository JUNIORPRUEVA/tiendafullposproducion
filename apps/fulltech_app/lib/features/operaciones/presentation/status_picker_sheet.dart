import 'package:flutter/material.dart';

class StatusPickerSheet {
  static const adminStatuses = <String>[
    'pendiente',
    'confirmada',
    'asignada',
    'en_camino',
    'en_proceso',
    'finalizada',
    'reagendada',
    'cancelada',
    'cerrada',
  ];

  static String label(String raw) {
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
      case 'cancelada':
      case 'cancelled':
        return 'Cancelado';
      case 'reagendada':
      case 'rescheduled':
        return 'Reagendada';
      case 'cerrada':
        return 'Cerrada';
      default:
        return raw;
    }
  }

  static IconData icon(String raw) {
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
      case 'cancelada':
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'reagendada':
      case 'rescheduled':
        return Icons.event_repeat_rounded;
      case 'cerrada':
        return Icons.lock_outline_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  static Future<String?> show(BuildContext context, {required String current}) {
    final normalized = current.trim().toLowerCase();

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cambiar estado',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      normalized.isEmpty ? '—' : label(normalized),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final state in adminStatuses)
                      ListTile(
                        leading: Icon(icon(state)),
                        title: Text(label(state)),
                        trailing: state == normalized
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, state),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
