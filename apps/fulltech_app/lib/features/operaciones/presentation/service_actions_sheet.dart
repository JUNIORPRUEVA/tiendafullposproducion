import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../operations_models.dart';
import 'service_pdf_exporter.dart';

class ServiceActionsSheet {
  static const adminPhases = <String>[
    'reserva',
    'confirmacion',
    'programacion',
    'ejecucion',
    'revision',
    'facturacion',
    'cierre',
    'cancelada',
  ];

  static List<String> allowedNextAdminPhases(String current) {
    final normalized = current.trim().toLowerCase();
    if (normalized.isEmpty) return const ['cancelada'];
    if (normalized == 'cancelada' || normalized == 'cierre') return const [];

    const linear = <String>[
      'reserva',
      'confirmacion',
      'programacion',
      'ejecucion',
      'revision',
      'facturacion',
      'cierre',
    ];

    final idx = linear.indexOf(normalized);
    if (idx < 0) return const ['cancelada'];
    final nextIdx = idx + 1;
    final next = nextIdx < linear.length ? linear[nextIdx] : null;
    if (next == null) return const [];
    return [next, 'cancelada'];
  }

  static Future<String?> pickAdminPhase(
    BuildContext context, {
    required String current,
    List<String>? allowed,
  }) {
    final normalized = current.trim().toLowerCase();
    final options = (allowed ?? allowedNextAdminPhases(normalized))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);

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
                        'Cambiar fase',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      normalized.isEmpty ? '—' : adminPhaseLabel(normalized),
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
                    if (options.isEmpty)
                      const ListTile(
                        leading: Icon(Icons.info_outline_rounded),
                        title: Text('No hay transiciones disponibles'),
                      )
                    else
                      for (final phase in options)
                        ListTile(
                          leading: const Icon(Icons.flag_outlined),
                          title: Text(adminPhaseLabel(phase)),
                          trailing: phase == normalized
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, phase),
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
    bool canChangeAdminPhase = false,
    String? changeAdminPhaseDeniedReason,
    Future<void> Function(String adminPhase)? onChangeAdminPhase,
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

        final changeAdminPhase = onChangeAdminPhase;
        final changePhase = onChangePhase;

        final canChangeStatus = allowedStatusTargets.isNotEmpty;
        final canChangePhaseEffective = changePhase != null && canChangePhase;
        final canChangeAdminPhaseEffective =
            changeAdminPhase != null && canChangeAdminPhase;

        final phaseSubtitle = effectiveServicePhaseLabel(service);
        final adminPhaseRaw = (service.adminPhase ?? '').trim();
        final adminPhaseSubtitle = adminPhaseRaw.isEmpty
            ? '—'
            : adminPhaseLabel(adminPhaseRaw);

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
                  subtitle: 'Actual: ${effectiveServiceStatusLabel(service)}',
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
                  title: 'Cambiar fase operativa',
                  subtitle: 'Actual: $phaseSubtitle',
                  enabled: canChangePhaseEffective,
                  disabledReason:
                      changePhaseDeniedReason ?? 'Solo creador o admin',
                  onTap: !canChangePhaseEffective
                      ? null
                      : () async {
                          final draft =
                              await _pickServicePhaseWithScheduleAndNote(
                                context,
                                current: service.phase,
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
                            () => changePhase(next, scheduledAt, draft['note']),
                          );
                        },
                ),
                item(
                  icon: Icons.account_tree_outlined,
                  title: 'Cambiar fase administrativa',
                  subtitle: 'Actual: $adminPhaseSubtitle',
                  enabled: canChangeAdminPhaseEffective,
                  disabledReason:
                      changeAdminPhaseDeniedReason ?? 'No autorizado',
                  onTap: !canChangeAdminPhaseEffective
                      ? null
                      : () async {
                          final current = (service.adminPhase ?? 'reserva')
                              .trim();
                          final next = await pickAdminPhase(
                            context,
                            current: current,
                          );
                          if (next == null) return;
                          await closeAnd(() => changeAdminPhase(next));
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
                (service.status == 'completed' || service.status == 'closed')
                    ? item(
                        icon: Icons.verified_outlined,
                        title: 'Crear garantía',
                        enabled: canOperate,
                        disabledReason: operateDeniedReason,
                        onTap: () => closeAnd(onCreateWarranty),
                      )
                    : const SizedBox.shrink(),
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

                canDelete ? groupTitle('Peligro') : const SizedBox.shrink(),
                canDelete
                    ? item(
                        icon: Icons.delete_outline,
                        title: 'Eliminar',
                        subtitle: 'Esta acción no se puede deshacer',
                        color: scheme.error,
                        enabled: canDelete,
                        disabledReason: deleteDeniedReason,
                        onTap: () => closeAnd(onDelete),
                      )
                    : const SizedBox.shrink(),

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
    'levantamiento',
    'instalacion',
    'mantenimiento',
    'garantia',
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
    if (!context.mounted) return null;
    if (date == null) return null;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!context.mounted) return null;
    if (time == null) return null;

    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  static Future<Map<String, String?>?> _pickServicePhaseWithScheduleAndNote(
    BuildContext context, {
    required String current,
    DateTime? initialScheduledAt,
  }) {
    final normalized = current.trim().toLowerCase();

    final noteCtrl = TextEditingController();

    return showModalBottomSheet<Map<String, String?>>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      builder: (context) {
        final phaseOptions = _servicePhases
            .where((phase) => phase != normalized)
            .toList(growable: false);
        final initialPhase = phaseOptions.isNotEmpty
            ? phaseOptions.first
            : _servicePhases.first;
        var selected = initialPhase;
        DateTime? scheduledAt = initialScheduledAt;

        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            const titleColor = Color(0xFF10233F);
            const bodyColor = Color(0xFF5B6B82);
            const outlineColor = Color(0xFFD9E7F5);
            const surfaceColor = Color(0xFFFFFFFF);
            const softSurfaceColor = Color(0xFFF4F9FF);
            const accentSoftColor = Color(0xFFE0F2FE);
            const accentMidColor = Color(0xFFBAE6FD);
            const accentStrongColor = Color(0xFF0B6BDE);
            final formattedSchedule = scheduledAt == null
                ? 'Seleccionar fecha y hora'
                : '${MaterialLocalizations.of(context).formatCompactDate(scheduledAt!)} · ${TimeOfDay.fromDateTime(scheduledAt!).format(context)}';

            Widget phaseCard(String phase) {
              final isSelected = selected == phase;
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() => selected = phase),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [accentSoftColor, Color(0xFFDDF1FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [surfaceColor, softSurfaceColor],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    border: Border.all(
                      color: isSelected ? accentMidColor : outlineColor,
                    ),
                    boxShadow: isSelected
                        ? const [
                            BoxShadow(
                              color: Color(0x140B6BDE),
                              blurRadius: 14,
                              offset: Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? accentStrongColor.withValues(alpha: 0.12)
                              : const Color(0xFFEAF3FF),
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.flag_rounded
                              : Icons.outlined_flag_rounded,
                          size: 16,
                          color: isSelected ? accentStrongColor : bodyColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          phaseLabel(phase),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 8,
                  bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFF8FBFF),
                        Color(0xFFEAF4FF),
                        Color(0xFFFFFFFF),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: outlineColor),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F172A),
                        blurRadius: 28,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: accentMidColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Cambiar fase operativa',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: titleColor,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Selecciona la siguiente etapa y agenda el movimiento.',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: bodyColor,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: accentSoftColor,
                                border: Border.all(color: accentMidColor),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Actual',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: bodyColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    phaseLabel(normalized),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: accentStrongColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        GridView.builder(
                          shrinkWrap: true,
                          itemCount: phaseOptions.length,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                mainAxisExtent: 60,
                              ),
                          itemBuilder: (context, index) {
                            return phaseCard(phaseOptions[index]);
                          },
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            final picked = await _pickDateTime(
                              context,
                              initial: scheduledAt,
                            );
                            if (!context.mounted) return;
                            if (picked == null) return;
                            setState(() => scheduledAt = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: softSurfaceColor,
                              border: Border.all(color: outlineColor),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: accentSoftColor,
                                  ),
                                  child: Icon(
                                    Icons.schedule_rounded,
                                    color: accentStrongColor,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Fecha y hora',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: bodyColor,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        formattedSchedule,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: titleColor,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: bodyColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: noteCtrl,
                          minLines: 2,
                          maxLines: 2,
                          style: const TextStyle(color: titleColor),
                          decoration: InputDecoration(
                            labelText: 'Nota opcional',
                            labelStyle: const TextStyle(color: bodyColor),
                            hintText: 'Agrega un detalle breve para el cambio.',
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                            ),
                            filled: true,
                            fillColor: softSurfaceColor,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: outlineColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: outlineColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: accentStrongColor.withValues(
                                  alpha: 0.70,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: titleColor,
                                  side: const BorderSide(color: outlineColor),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: scheduledAt == null
                                    ? null
                                    : () {
                                        final note = noteCtrl.text.trim();
                                        Navigator.pop(context, {
                                          'phase': selected,
                                          'scheduledAt': scheduledAt!
                                              .toIso8601String(),
                                          'note': note.isEmpty ? null : note,
                                        });
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor: scheme.primary,
                                  foregroundColor: scheme.onPrimary,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text('Aplicar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(noteCtrl.dispose);
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
