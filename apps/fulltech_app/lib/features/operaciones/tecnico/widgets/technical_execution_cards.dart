import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/local_file_image.dart';
import '../../operations_models.dart';
import '../technical_evidence_upload.dart';

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

class ExecutionChecklistItem {
  final String key;
  final String label;
  final bool required;

  const ExecutionChecklistItem({
    required this.key,
    required this.label,
    this.required = true,
  });
}

class DynamicExecutionChecklistCard extends StatelessWidget {
  final String title;
  final List<ExecutionChecklistItem> items;
  final Map<String, dynamic> checklistData;
  final void Function(String key, bool next) onChanged;

  const DynamicExecutionChecklistCard({
    super.key,
    this.title = 'Checklist del servicio',
    required this.items,
    required this.checklistData,
    required this.onChanged,
  });

  bool _valueFor(String key) {
    final rawItems = checklistData['items'];
    if (rawItems is Map) {
      return rawItems[key] == true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (items.isEmpty) {
      return TechnicalSectionCard(
        icon: Icons.playlist_add_check_outlined,
        title: title,
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

    final requiredItems = items.where((i) => i.required).toList();
    final completedRequired = requiredItems
        .where((i) => _valueFor(i.key))
        .length;
    final requiredTotal = requiredItems.length;

    return TechnicalSectionCard(
      icon: Icons.playlist_add_check_outlined,
      title: title,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$completedRequired/$requiredTotal',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
      child: Column(
        children: [
          for (final item in items) ...[
            Stack(
              children: [
                _ChecklistTile(
                  label: item.label,
                  done: _valueFor(item.key),
                  onTap: () => onChanged(item.key, !_valueFor(item.key)),
                ),
                if (!item.required)
                  Positioned(
                    top: 8,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'OPC',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (item != items.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class EvidenceGalleryCard extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final String uploadLabel;
  final IconData icon;
  final List<ServiceFileModel> files;
  final List<PendingEvidenceUpload> pending;
  final VoidCallback? onUpload;
  final Widget? trailing;
  final void Function(ServiceFileModel file) onPreview;

  const EvidenceGalleryCard({
    super.key,
    this.title = 'Evidencias del servicio',
    this.emptyLabel = 'Sin evidencias aún',
    this.uploadLabel = 'Subir evidencia',
    this.icon = Icons.photo_camera_outlined,
    required this.files,
    required this.pending,
    this.onUpload,
    this.trailing,
    required this.onPreview,
  });

  bool _isLikelyImage(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('image')) return true;
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp');
  }

  bool _isLikelyVideo(ServiceFileModel file) {
    final ft = (file.mimeType ?? file.fileType).trim().toLowerCase();
    final url = file.fileUrl.trim().toLowerCase();
    if (ft.contains('video')) return true;
    return url.endsWith('.mp4');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final trailingWidget =
        trailing ??
        (onUpload == null
            ? null
            : FilledButton.tonalIcon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(uploadLabel),
              ));

    final hasAny = files.isNotEmpty || pending.isNotEmpty;

    if (!hasAny) {
      return TechnicalSectionCard(
        icon: icon,
        title: title,
        trailing: trailingWidget,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  emptyLabel,
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
      icon: icon,
      title: title,
      trailing: trailingWidget,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // Make thumbnails as small/dense as possible while keeping them tappable.
          final crossAxisCount = w >= 900
              ? 8
              : (w >= 700 ? 6 : (w >= 520 ? 5 : (w >= 420 ? 4 : 3)));

          final totalCount = pending.length + files.length;

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemCount: totalCount,
            itemBuilder: (context, index) {
              if (index < pending.length) {
                final item = pending[index];
                return _PendingEvidenceTile(item: item);
              }

              final file = files[index - pending.length];
              final isImage = _isLikelyImage(file);
              final isVideo = _isLikelyVideo(file);
              final caption = (file.caption ?? '').trim();

              return InkWell(
                onTap: () => onPreview(file),
                borderRadius: BorderRadius.circular(10),
                child: Ink(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (isImage)
                          Image.network(
                            file.fileUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) {
                              return _FilePlaceholder(file: file);
                            },
                          )
                        else if (isVideo)
                          const _VideoPlaceholder()
                        else
                          _FilePlaceholder(file: file),
                        if (isVideo)
                          Builder(
                            builder: (context) {
                              final cs = Theme.of(context).colorScheme;
                              return Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  size: 54,
                                  color: cs.onSurface.withValues(alpha: 0.70),
                                ),
                              );
                            },
                          ),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _TypeBadge(
                            icon: isVideo
                                ? Icons.play_circle_outline
                                : (isImage
                                      ? Icons.photo_outlined
                                      : Icons.insert_drive_file_outlined),
                            label: isVideo
                                ? 'VIDEO'
                                : (isImage ? 'IMG' : 'FILE'),
                          ),
                        ),
                        if (caption.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.92,
                              ),
                              child: Text(
                                caption,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _PendingEvidenceTile extends StatelessWidget {
  final PendingEvidenceUpload item;

  const _PendingEvidenceTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final caption = item.caption.trim();

    Widget preview;
    if (item.isImage && item.bytes != null) {
      preview = Image.memory(
        Uint8List.fromList(item.bytes!),
        fit: BoxFit.cover,
      );
    } else if (item.isImage && (item.path ?? '').trim().isNotEmpty) {
      preview = localFileImage(path: item.path!.trim(), fit: BoxFit.cover);
    } else {
      preview = Stack(
        fit: StackFit.expand,
        children: [
          Container(color: cs.surfaceContainerHighest),
          Center(
            child: Icon(
              item.isVideo
                  ? Icons.play_circle_outline
                  : Icons.upload_file_outlined,
              size: 52,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final percent = (item.progress * 100).round();

    return Ink(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            preview,
            Positioned(
              top: 8,
              left: 8,
              child: _TypeBadge(
                icon: item.isVideo
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_upload_outlined,
                label: 'SUBIENDO',
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: item.progress <= 0 ? null : item.progress,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          percent > 0 ? '$percent% • Subiendo…' : 'Subiendo…',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (caption.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
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
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    cs.onSurface.withValues(alpha: 0.10),
                    cs.onSurface.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.videocam_outlined,
              size: 42,
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TypeBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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
