import 'package:flutter/material.dart';

class StatusPickerSheet {
  static const orderStates = <String>[
    'pending',
    'confirmed',
    'assigned',
    'in_progress',
    'finalized',
    'cancelled',
    'rescheduled',
  ];

  static String label(String raw) {
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
      default:
        return raw;
    }
  }

  static IconData icon(String raw) {
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
                    for (final state in orderStates)
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
