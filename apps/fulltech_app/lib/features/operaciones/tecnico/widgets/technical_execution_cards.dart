import 'package:flutter/material.dart';

import '../../operations_models.dart';

class TechnicalSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;

  const TechnicalSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class ServiceHeaderCard extends StatelessWidget {
  final ServiceModel service;

  const ServiceHeaderCard({super.key, required this.service});

  String _firstNonEmpty(List<String> values, {String fallback = '—'}) {
    for (final v in values) {
      final t = v.trim();
      if (t.isNotEmpty) return t;
    }
    return fallback;
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final d = v.day.toString().padLeft(2, '0');
    final m = v.month.toString().padLeft(2, '0');
    final y = v.year.toString();
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final customer = _firstNonEmpty([
      service.customerName,
    ], fallback: 'Cliente');
    final workTitle = _firstNonEmpty([
      service.title,
      service.description,
    ], fallback: 'Servicio');

    final workMeta = [
      if (service.serviceType.trim().isNotEmpty) service.serviceType.trim(),
      if (service.category.trim().isNotEmpty) service.category.trim(),
    ].join(' · ');

    final scheduledLabel = service.scheduledStart != null
        ? _fmtDate(service.scheduledStart)
        : (service.scheduledEnd != null ? _fmtDate(service.scheduledEnd) : '—');

    return Card(
      elevation: 1,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  child: const Icon(Icons.person_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        workTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (workMeta.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Trabajo: $workMeta',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.build_outlined,
                  label: service.orderType.trim().isNotEmpty
                      ? service.orderType.trim()
                      : 'Orden',
                ),
                _InfoPill(
                  icon: Icons.flag_outlined,
                  label: 'Fase: ${phaseLabel(service.currentPhase)}',
                ),
                _InfoPill(
                  icon: Icons.playlist_add_check_circle_outlined,
                  label: service.orderState.trim().isNotEmpty
                      ? service.orderState.trim()
                      : service.status.trim(),
                ),
                _InfoPill(icon: Icons.event_outlined, label: scheduledLabel),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.customerAddress.trim().isEmpty
                        ? 'Dirección no disponible'
                        : service.customerAddress.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExecutionTimelineCard extends StatelessWidget {
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  final VoidCallback onArrived;
  final VoidCallback onStarted;
  final VoidCallback onFinished;

  const ExecutionTimelineCard({
    super.key,
    required this.arrivedAt,
    required this.startedAt,
    required this.finishedAt,
    required this.onArrived,
    required this.onStarted,
    required this.onFinished,
  });

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '—';
    final v = dt.toLocal();
    final h = v.hour.toString().padLeft(2, '0');
    final m = v.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  _StepVisualState _stateFor(
    int index,
    DateTime? arrived,
    DateTime? started,
    DateTime? finished,
  ) {
    final steps = [arrived, started, finished];
    final cur = steps[index];
    if (cur != null) return _StepVisualState.completed;

    // Active = first missing step after the last completed.
    final firstMissing = steps.indexWhere((d) => d == null);
    if (firstMissing == index) return _StepVisualState.active;

    return _StepVisualState.pending;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final s0 = _stateFor(0, arrivedAt, startedAt, finishedAt);
    final s1 = _stateFor(1, arrivedAt, startedAt, finishedAt);
    final s2 = _stateFor(2, arrivedAt, startedAt, finishedAt);

    return TechnicalSectionCard(
      icon: Icons.timeline,
      title: 'Ejecución',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _TimelineStepButton(
                  label: 'Llegada',
                  time: _fmtTime(arrivedAt),
                  state: s0,
                  onTap: onArrived,
                  icon: Icons.place_outlined,
                ),
              ),
              _TimelineConnector(state: s0 == _StepVisualState.completed),
              Expanded(
                child: _TimelineStepButton(
                  label: 'Inicio',
                  time: _fmtTime(startedAt),
                  state: s1,
                  onTap: onStarted,
                  icon: Icons.play_circle_outline_rounded,
                ),
              ),
              _TimelineConnector(state: s1 == _StepVisualState.completed),
              Expanded(
                child: _TimelineStepButton(
                  label: 'Finalizar',
                  time: _fmtTime(finishedAt),
                  state: s2,
                  onTap: onFinished,
                  icon: Icons.check_circle_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toca cada etapa para registrar la hora.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ClientApprovalCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ClientApprovalCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TechnicalSectionCard(
      icon: Icons.verified_outlined,
      title: 'Aprobación del cliente',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Cliente conforme con el trabajo.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch.adaptive(value: value, onChanged: onChanged),
              ],
            ),
          ),
          if (value) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Text(
                    'Cliente conforme',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TechnicalNotesCard extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  const TechnicalNotesCard({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TechnicalSectionCard(
      icon: Icons.edit_note_outlined,
      title: 'Notas del técnico',
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        minLines: 4,
        maxLines: 8,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText:
              'Describe lo que hiciste, cambios realizados o recomendaciones.',
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.all(14),
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class ServiceChecklistCard extends StatelessWidget {
  final List<ServiceStepModel> steps;
  final Future<void> Function(ServiceStepModel step, bool next) onToggle;

  const ServiceChecklistCard({
    super.key,
    required this.steps,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (steps.isEmpty) {
      return TechnicalSectionCard(
        icon: Icons.playlist_add_check_outlined,
        title: 'Checklist de servicio',
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.playlist_remove_outlined, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sin checklist',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return TechnicalSectionCard(
      icon: Icons.playlist_add_check_outlined,
      title: 'Checklist de servicio',
      child: Column(
        children: [
          for (final step in steps) ...[
            _ChecklistTile(
              label: step.stepLabel,
              done: step.isDone,
              onTap: () => onToggle(step, !step.isDone),
            ),
            if (step != steps.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class EvidenceGalleryCard extends StatelessWidget {
  final List<ServiceFileModel> files;
  final VoidCallback onUpload;
  final void Function(ServiceFileModel file) onPreview;

  const EvidenceGalleryCard({
    super.key,
    required this.files,
    required this.onUpload,
    required this.onPreview,
  });

  bool _isLikelyImage(ServiceFileModel file) {
    final ft = file.fileType.trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('image')) return true;
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final trailing = FilledButton.tonalIcon(
      onPressed: onUpload,
      icon: const Icon(Icons.upload_file_outlined),
      label: const Text('Subir evidencia'),
    );

    if (files.isEmpty) {
      return TechnicalSectionCard(
        icon: Icons.photo_camera_outlined,
        title: 'Evidencias del servicio',
        trailing: trailing,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.photo_camera_outlined, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sin evidencias aún',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return TechnicalSectionCard(
      icon: Icons.photo_camera_outlined,
      title: 'Evidencias del servicio',
      trailing: trailing,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final crossAxisCount = w >= 700 ? 4 : (w >= 420 ? 3 : 2);

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final isImage = _isLikelyImage(file);

              return InkWell(
                onTap: () => onPreview(file),
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: isImage
                        ? Image.network(
                            file.fileUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) {
                              return _FilePlaceholder(file: file);
                            },
                          )
                        : _FilePlaceholder(file: file),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ServiceChangesCard extends StatelessWidget {
  final List<ServiceExecutionChangeModel> changes;
  final VoidCallback onAdd;
  final bool Function(ServiceExecutionChangeModel change) canDelete;
  final void Function(ServiceExecutionChangeModel change) onDelete;

  const ServiceChangesCard({
    super.key,
    required this.changes,
    required this.onAdd,
    required this.canDelete,
    required this.onDelete,
  });

  String _fmtNum(num? v) {
    if (v == null) return '';
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TechnicalSectionCard(
      icon: Icons.change_circle_outlined,
      title: 'Cambios o novedades del servicio',
      trailing: FilledButton.tonalIcon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Agregar novedad'),
      ),
      child: changes.isEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.inbox_outlined, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sin cambios registrados',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (final c in changes) ...[
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        c.type.trim().isEmpty
                            ? c.description
                            : '${c.type}: ${c.description}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (c.quantity != null)
                              _MetaChip(
                                icon: Icons.numbers,
                                label: 'Qty: ${_fmtNum(c.quantity)}',
                              ),
                            if (c.extraCost != null)
                              _MetaChip(
                                icon: Icons.attach_money,
                                label: 'Extra: ${_fmtNum(c.extraCost)}',
                              ),
                            if (c.clientApproved == true)
                              _MetaChip(
                                icon: Icons.verified,
                                label: 'Aprobado',
                              ),
                            if ((c.note ?? '').trim().isNotEmpty)
                              _MetaChip(
                                icon: Icons.note_outlined,
                                label: 'Nota: ${(c.note ?? '').trim()}',
                              ),
                          ],
                        ),
                      ),
                      trailing: canDelete(c)
                          ? IconButton(
                              tooltip: 'Eliminar',
                              onPressed: () => onDelete(c),
                              icon: const Icon(Icons.delete_outline),
                            )
                          : null,
                    ),
                  ),
                  if (c != changes.last) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurface),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  final String label;
  final bool done;
  final VoidCallback onTap;

  const _ChecklistTile({
    required this.label,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Transform.scale(
                scale: 1.15,
                child: Checkbox.adaptive(
                  value: done,
                  onChanged: (_) => onTap(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilePlaceholder extends StatelessWidget {
  final ServiceFileModel file;

  const _FilePlaceholder({required this.file});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.all(10),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insert_drive_file_outlined, color: cs.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(
              file.fileType.trim().isEmpty ? 'Archivo' : file.fileType.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StepVisualState { pending, active, completed }

class _TimelineStepButton extends StatelessWidget {
  final String label;
  final String time;
  final IconData icon;
  final _StepVisualState state;
  final VoidCallback onTap;

  const _TimelineStepButton({
    required this.label,
    required this.time,
    required this.icon,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color bg;
    Color fg;
    IconData stateIcon;

    switch (state) {
      case _StepVisualState.completed:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        stateIcon = Icons.check_circle;
        break;
      case _StepVisualState.active:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        stateIcon = Icons.timelapse;
        break;
      case _StepVisualState.pending:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
        stateIcon = Icons.radio_button_unchecked;
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(stateIcon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  final bool state;

  const _TimelineConnector({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: 16,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: state ? cs.primary : cs.outlineVariant,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}
