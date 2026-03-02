import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../operations_models.dart';
import 'service_pdf_exporter.dart';

class ServiceActionsSheet {
  static Future<Map<String, String?>?> pickChangePhaseDraft(
    BuildContext context, {
    required String current,
    DateTime? initialScheduledAt,
  }) {
    return _pickServicePhaseWithScheduleAndNote(
      context,
      current: current,
      initialScheduledAt: initialScheduledAt,
    );
  }

  static Future<void> show(
    BuildContext context, {
    required ServiceModel service,
    required bool canOperate,
    String? operateDeniedReason,
    required bool canEdit,
    String? editDeniedReason,
    bool canChangePhase = false,
    String? changePhaseDeniedReason,
    Future<void> Function(String phase, DateTime scheduledAt, String? note)?
    onChangePhase,
    required List<String> allowedStatusTargets,
    required bool canDelete,
    String? deleteDeniedReason,
    required Future<void> Function() onEdit,
    required Future<void> Function(String status) onChangeStatus,
    required Future<void> Function() onPickSchedule,
    required Future<void> Function() onAssignTechs,
    required Future<void> Function() onUploadEvidence,
    required Future<void> Function() onCreateWarranty,
    required Future<void> Function() onDelete,
    required Future<void> Function(String message) onAddNote,
    required Future<void> Function(String reason) onMarkPendingBy,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;

        Widget groupTitle(String text) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.onSurface.withValues(alpha: 0.70),
              ),
            ),
          );
        }

        Widget item({
          required IconData icon,
          required String title,
          String? subtitle,
          required Future<void> Function()? onTap,
          bool enabled = true,
          String? disabledReason,
          Color? color,
        }) {
          final effectiveColor = color ?? scheme.onSurface;
          final disabled = !enabled;
          final paint = disabled
              ? effectiveColor.withValues(alpha: 0.42)
              : effectiveColor;
          return ListTile(
            leading: Icon(icon, color: paint),
            title: Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w800, color: paint),
            ),
            subtitle: subtitle == null ? null : Text(subtitle),
            onTap: () async {
              if (disabled) {
                final msg = (disabledReason ?? '').trim();
                if (msg.isNotEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(msg)));
                }
                return;
              }
              if (onTap == null) return;
              await onTap();
            },
          );
        }

        Future<void> closeAnd(Future<void> Function() action) async {
          Navigator.pop(context);
          await action();
        }

        final canChangeStatus = allowedStatusTargets.isNotEmpty;
        final canChangePhaseEffective = onChangePhase != null && canChangePhase;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Text(
                    'Acciones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),

                groupTitle('Estado'),
                item(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Cambiar estado',
                  subtitle: 'Actual: ${service.status}',
                  enabled: canChangeStatus,
                  disabledReason: canOperate
                      ? 'No hay transiciones disponibles'
                      : (operateDeniedReason ?? 'No autorizado'),
                  onTap: !canChangeStatus
                      ? null
                      : () async {
                          final next = await _pickServiceStatus(
                            context,
                            current: service.status,
                            allowed: allowedStatusTargets,
                          );
                          if (next == null) return;
                          await closeAnd(() => onChangeStatus(next));
                        },
                ),
                item(
                  icon: Icons.flag_outlined,
                  title: 'Cambiar fase',
                  subtitle: 'Actual: ${phaseLabel(service.currentPhase)}',
                  enabled: canChangePhaseEffective,
                  disabledReason:
                      (changePhaseDeniedReason ?? 'Solo creador o admin'),
                  onTap: onChangePhase == null
                      ? null
                      : () async {
                          final draft =
                              await _pickServicePhaseWithScheduleAndNote(
                                context,
                                current: service.currentPhase,
                                initialScheduledAt: service.scheduledStart,
                              );
                          if (draft == null) return;
                          final next = (draft['phase'] ?? '').trim();
                          final scheduledAtRaw = (draft['scheduledAt'] ?? '')
                              .trim();
                          if (next.isEmpty) return;
                          final scheduledAt = DateTime.tryParse(scheduledAtRaw);
                          if (scheduledAt == null) return;
                          await closeAnd(
                            () =>
                                onChangePhase(next, scheduledAt, draft['note']),
                          );
                        },
                ),
                item(
                  icon: Icons.location_on_outlined,
                  title: 'Marcar: Llegué al sitio',
                  enabled: canOperate,
                  disabledReason: operateDeniedReason,
                  onTap: () => closeAnd(() => onAddNote('Llegué al sitio')),
                ),
                item(
                  icon: Icons.play_circle_outline,
                  title: 'Marcar: Inicié',
                  enabled: canOperate,
                  disabledReason: operateDeniedReason,
                  onTap: () => closeAnd(() => onAddNote('Inicié trabajo')),
                ),
                item(
                  icon: Icons.check_circle_outline,
                  title: 'Marcar: Finalicé',
                  enabled: canOperate,
                  disabledReason: operateDeniedReason,
                  onTap: () => closeAnd(() => onAddNote('Finalicé trabajo')),
                ),
                item(
                  icon: Icons.pending_actions_outlined,
                  title: 'Marcar: Pendiente por…',
                  enabled: canOperate,
                  disabledReason: operateDeniedReason,
                  onTap: () async {
                    final reason = await _askReason(context);
                    if (reason == null || reason.trim().isEmpty) return;
                    await closeAnd(() => onMarkPendingBy(reason.trim()));
                  },
                ),

                groupTitle('Gestión'),
                item(
                  icon: Icons.edit_outlined,
                  title: 'Editar',
                  enabled: canEdit,
                  disabledReason: editDeniedReason ?? 'Solo creador o admin',
                  onTap: () => closeAnd(onEdit),
                ),
                item(
                  icon: Icons.event_available_outlined,
                  title: 'Agendar / Reagendar',
                  enabled: canOperate,
                  disabledReason: operateDeniedReason,
                  onTap: () => closeAnd(onPickSchedule),
                ),
                item(
                  icon: Icons.groups_outlined,
                  title: 'Asignar técnicos',
                  enabled: canOperate,
                  disabledReason: operateDeniedReason,
                  onTap: () => closeAnd(onAssignTechs),
                ),
                item(
                  icon: Icons.attach_file,
                  title: 'Subir evidencia',
                  enabled: canOperate,
                  disabledReason: operateDeniedReason,
                  onTap: () => closeAnd(onUploadEvidence),
                ),
                if (service.status == 'completed' || service.status == 'closed')
                  item(
                    icon: Icons.verified_outlined,
                    title: 'Crear garantía',
                    enabled: canOperate,
                    disabledReason: operateDeniedReason,
                    onTap: () => closeAnd(onCreateWarranty),
                  ),
                item(
                  icon: Icons.person_outline,
                  title: 'Ver cliente',
                  onTap: service.customerId.trim().isEmpty
                      ? null
                      : () async {
                          Navigator.pop(context);
                          context.push(
                            Routes.clienteDetail(service.customerId.trim()),
                          );
                        },
                ),
                item(
                  icon: Icons.receipt_long_outlined,
                  title: 'Ver cotizaciones',
                  onTap: service.customerPhone.trim().isEmpty
                      ? null
                      : () async {
                          final phone = service.customerPhone.trim();
                          Navigator.pop(context);
                          context.push(
                            '${Routes.cotizacionesHistorial}?customerPhone=${Uri.encodeQueryComponent(phone)}&pick=0',
                          );
                        },
                ),

                groupTitle('Documentos'),
                item(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Exportar PDF (detalle completo)',
                  subtitle: ServicePdfExporter.isSupported
                      ? 'Compartir o guardar'
                      : 'No disponible en esta plataforma',
                  onTap: () async {
                    Navigator.pop(context);
                    await ServicePdfExporter.share(context, service);
                  },
                ),

                if (canDelete) ...[
                  groupTitle('Peligro'),
                  item(
                    icon: Icons.delete_outline,
                    title: 'Eliminar',
                    subtitle: 'Esta acción no se puede deshacer',
                    color: scheme.error,
                    enabled: canDelete,
                    disabledReason: deleteDeniedReason,
                    onTap: () => closeAnd(onDelete),
                  ),
                ],

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  static const _serviceStatuses = <String>[
    'reserved',
    'survey',
    'scheduled',
    'in_progress',
    'completed',
    'warranty',
    'closed',
    'cancelled',
  ];

  static String _serviceStatusLabel(String raw) {
    switch (raw) {
      case 'reserved':
        return 'Reserva';
      case 'survey':
        return 'Levantamiento';
      case 'scheduled':
        return 'Agendado';
      case 'in_progress':
        return 'En proceso';
      case 'completed':
        return 'Finalizado';
      case 'warranty':
        return 'Garantía';
      case 'closed':
        return 'Cerrado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return raw;
    }
  }

  static const _servicePhases = <String>[
    'instalacion',
    'mantenimiento',
    'garantia',
    'levantamiento',
  ];

  static Future<DateTime?> _pickDateTime(
    BuildContext context, {
    DateTime? initial,
  }) async {
    final now = DateTime.now();
    final base = initial ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  static Future<Map<String, String?>?> _pickServicePhaseWithScheduleAndNote(
    BuildContext context, {
    required String current,
    DateTime? initialScheduledAt,
  }) {
    final normalized = current.trim().toLowerCase();

    return showModalBottomSheet<Map<String, String?>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final initialPhase = _servicePhases.contains(normalized)
            ? normalized
            : _servicePhases.first;
        var selected = initialPhase;
        DateTime? scheduledAt = initialScheduledAt;
        final noteCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Cambiar fase',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            phaseLabel(normalized),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.70),
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
                          for (final p in _servicePhases)
                            RadioListTile<String>(
                              value: p,
                              groupValue: selected,
                              title: Text(phaseLabel(p)),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => selected = value);
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final picked = await _pickDateTime(
                                  context,
                                  initial: scheduledAt,
                                );
                                if (picked == null) return;
                                setState(() => scheduledAt = picked);
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Nueva fecha y hora (obligatorio)',
                                  border: OutlineInputBorder(),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        scheduledAt == null
                                            ? 'Seleccionar…'
                                            : MaterialLocalizations.of(context)
                                                      .formatFullDate(
                                                        scheduledAt!,
                                                      )
                                                      .toString()
                                                      .replaceAll(',', '') +
                                                  '  ' +
                                                  TimeOfDay.fromDateTime(
                                                    scheduledAt!,
                                                  ).format(context),
                                      ),
                                    ),
                                    const Icon(Icons.schedule_outlined),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                            child: TextField(
                              controller: noteCtrl,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'Nota (opcional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      noteCtrl.dispose();
                                      Navigator.pop(context);
                                    },
                                    child: const Text('Cancelar'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: scheduledAt == null
                                        ? null
                                        : () {
                                            final note = noteCtrl.text.trim();
                                            noteCtrl.dispose();
                                            Navigator.pop(context, {
                                              'phase': selected,
                                              'scheduledAt': scheduledAt!
                                                  .toIso8601String(),
                                              'note': note.isEmpty
                                                  ? null
                                                  : note,
                                            });
                                          },
                                    child: const Text('Aplicar'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<String?> _pickServiceStatus(
    BuildContext context, {
    required String current,
    required List<String> allowed,
  }) {
    final normalized = current.trim().toLowerCase();
    final allowedSet = allowed.map((e) => e.trim().toLowerCase()).toSet();

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
                      _serviceStatusLabel(normalized),
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
                    for (final s in _serviceStatuses)
                      ListTile(
                        title: Text(_serviceStatusLabel(s)),
                        trailing: s == normalized
                            ? const Icon(Icons.check_rounded)
                            : null,
                        enabled: allowedSet.contains(s),
                        onTap: allowedSet.contains(s)
                            ? () => Navigator.pop(context, s)
                            : null,
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

  static Future<String?> _askReason(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motivo pendiente'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    return ok == true ? text : null;
  }
}
