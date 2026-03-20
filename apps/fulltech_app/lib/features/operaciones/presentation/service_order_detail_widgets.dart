import 'package:flutter/material.dart';

import '../operations_models.dart';
import 'photo_preview.dart';

enum OrderActionsMenuAction { call, location, quote, invoice, others }

class OrderInfoItem {
  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  const OrderInfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });
}

class OrderEvidenceItem {
  final String id;
  final String title;
  final String url;
  final String typeLabel;
  final String? meta;
  final bool isImage;
  final bool isVideo;

  const OrderEvidenceItem({
    required this.id,
    required this.title,
    required this.url,
    required this.typeLabel,
    this.meta,
    this.isImage = false,
    this.isVideo = false,
  });
}

class OrderNoteEntry {
  final String message;
  final String meta;

  const OrderNoteEntry({required this.message, required this.meta});
}

class OrderHeader extends StatelessWidget {
  final String customerName;
  final String statusLabel;
  final Color statusBackground;
  final Color statusForeground;
  final String? priorityLabel;
  final String? categoryLabel;
  final String? serviceTypeLabel;
  final String? orderLabel;
  final Widget actionsMenu;

  const OrderHeader({
    super.key,
    required this.customerName,
    required this.statusLabel,
    required this.statusBackground,
    required this.statusForeground,
    required this.actionsMenu,
    this.priorityLabel,
    this.categoryLabel,
    this.serviceTypeLabel,
    this.orderLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chips = <Widget>[
      _HeaderBadge(
        label: statusLabel,
        background: statusBackground,
        foreground: statusForeground,
        icon: Icons.radio_button_checked_rounded,
      ),
      if ((priorityLabel ?? '').trim().isNotEmpty)
        _HeaderBadge(
          label: priorityLabel!.trim(),
          background: const Color(0xFFFFF1DB),
          foreground: const Color(0xFF9A5800),
          icon: Icons.priority_high_rounded,
        ),
      if ((categoryLabel ?? '').trim().isNotEmpty)
        _HeaderBadge(
          label: categoryLabel!.trim(),
          background: const Color(0xFFE9F5FF),
          foreground: const Color(0xFF145DA0),
          icon: Icons.category_outlined,
        ),
      if ((serviceTypeLabel ?? '').trim().isNotEmpty)
        _HeaderBadge(
          label: serviceTypeLabel!.trim(),
          background: const Color(0xFFEEF3FF),
          foreground: const Color(0xFF304E9A),
          icon: Icons.miscellaneous_services_outlined,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6FAFF), Color(0xFFEAF2FB)],
        ),
        border: Border.all(color: const Color(0xFFD9E6F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10233F).withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: const Color(0xFF10233F),
                      ),
                    ),
                    if ((orderLabel ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        orderLabel!.trim(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              actionsMenu,
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ],
      ),
    );
  }
}

class OrderActionsMenu extends StatelessWidget {
  final bool canCall;
  final bool canOpenLocation;
  final bool canOpenQuote;
  final bool canOpenInvoice;
  final Future<void> Function(OrderActionsMenuAction action) onSelected;

  const OrderActionsMenu({
    super.key,
    required this.canCall,
    required this.canOpenLocation,
    required this.canOpenQuote,
    required this.canOpenInvoice,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final items = <PopupMenuEntry<OrderActionsMenuAction>>[
      if (canCall)
        const PopupMenuItem(
          value: OrderActionsMenuAction.call,
          child: _ActionMenuRow(
            icon: Icons.call_outlined,
            label: 'Llamar',
          ),
        ),
      if (canOpenLocation)
        const PopupMenuItem(
          value: OrderActionsMenuAction.location,
          child: _ActionMenuRow(
            icon: Icons.location_on_outlined,
            label: 'Ubicación',
          ),
        ),
      if (canOpenQuote)
        const PopupMenuItem(
          value: OrderActionsMenuAction.quote,
          child: _ActionMenuRow(
            icon: Icons.request_quote_outlined,
            label: 'Cotización',
          ),
        ),
      if (canOpenInvoice)
        const PopupMenuItem(
          value: OrderActionsMenuAction.invoice,
          child: _ActionMenuRow(
            icon: Icons.receipt_long_outlined,
            label: 'Factura',
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: OrderActionsMenuAction.others,
        child: _ActionMenuRow(
          icon: Icons.tune_rounded,
          label: 'Otros',
        ),
      ),
    ];

    return PopupMenuButton<OrderActionsMenuAction>(
      tooltip: 'Acciones',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        onSelected(value);
      },
      itemBuilder: (_) => items,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD6E3EF)),
        ),
        child: const Icon(Icons.more_horiz_rounded),
      ),
    );
  }
}

class OrderInfoSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<OrderInfoItem> items;

  const OrderInfoSection({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return _DetailSurface(
      title: title,
      icon: icon,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = width >= 980 ? 3 : width >= 620 ? 2 : 1;
          final spacing = 8.0;
          final cardWidth =
              columns == 1 ? width : (width - ((columns - 1) * spacing)) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final item in items)
                SizedBox(
                  width: cardWidth,
                  child: _InfoPanel(item: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class EvidenceGallery extends StatelessWidget {
  final String? referenceText;
  final List<OrderEvidenceItem> items;
  final VoidCallback? onUpload;
  final Future<void> Function(OrderEvidenceItem item) onOpenItem;

  const EvidenceGallery({
    super.key,
    required this.items,
    required this.onOpenItem,
    this.referenceText,
    this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final imageItems = items.where((item) => item.isImage).toList(growable: false);
    final mediaItems = items.where((item) => !item.isImage).toList(growable: false);

    return _DetailSurface(
      title: 'Evidencias',
      icon: Icons.perm_media_outlined,
      trailing: onUpload == null
          ? null
          : TextButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('Subir'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((referenceText ?? '').trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCE7F3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.flag_outlined, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      referenceText!.trim(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: const Color(0xFF16324E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (imageItems.isEmpty && mediaItems.isEmpty)
            const _EmptyBlock(
              icon: Icons.image_not_supported_outlined,
              title: 'Sin evidencias registradas',
              message: 'Todavía no hay imágenes, videos ni referencias adjuntas a esta orden.',
            )
          else ...[
            if (imageItems.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width >= 860 ? 4 : width >= 560 ? 3 : 2;
                  final spacing = 10.0;
                  final tileWidth =
                      (width - ((crossAxisCount - 1) * spacing)) / crossAxisCount;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final item in imageItems)
                        SizedBox(
                          width: tileWidth,
                          child: _ImageEvidenceTile(item: item),
                        ),
                    ],
                  );
                },
              ),
            if (mediaItems.isNotEmpty) ...[
              if (imageItems.isNotEmpty) const SizedBox(height: 12),
              Column(
                children: [
                  for (final item in mediaItems) ...[
                    _MediaEvidenceTile(
                      item: item,
                      onTap: () => onOpenItem(item),
                    ),
                    if (item != mediaItems.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class NotesSection extends StatelessWidget {
  final String? note;
  final TextEditingController controller;
  final VoidCallback onSave;
  final List<OrderNoteEntry> recentEntries;

  const NotesSection({
    super.key,
    required this.controller,
    required this.onSave,
    this.note,
    this.recentEntries = const [],
  });

  @override
  Widget build(BuildContext context) {
    final hasPrimary = (note ?? '').trim().isNotEmpty;

    return _DetailSurface(
      title: 'Notas y observaciones',
      icon: Icons.notes_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPrimary)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCE6F0)),
              ),
              child: Text(
                note!.trim(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.38,
                  color: const Color(0xFF1B3048),
                ),
              ),
            )
          else
            const _EmptyBlock(
              icon: Icons.note_alt_outlined,
              title: 'Sin observaciones iniciales',
              message: 'Esta orden no tiene una nota principal registrada.',
            ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Agregar nota interna',
              filled: true,
              fillColor: const Color(0xFFF9FBFD),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Guardar nota'),
            ),
          ),
          if (recentEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Actividad reciente',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF10233F),
              ),
            ),
            const SizedBox(height: 10),
            for (final entry in recentEntries) ...[
              _NoteTimelineTile(entry: entry),
              if (entry != recentEntries.last) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class ChecklistSection extends StatelessWidget {
  final List<ServiceStepModel> steps;
  final String Function(DateTime? value) formatDate;

  const ChecklistSection({
    super.key,
    required this.steps,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final doneItems = steps
        .where((item) => item.isDone || item.doneAt != null)
        .toList(growable: false);

    return _DetailSurface(
      title: 'Checklist técnico',
      icon: Icons.checklist_rounded,
      child: doneItems.isEmpty
          ? const _EmptyBlock(
              icon: Icons.check_circle_outline_rounded,
              title: 'Sin checklist completado',
              message: 'Todavía no hay pasos marcados por el técnico para esta orden.',
            )
          : Column(
              children: [
                for (final item in doneItems) ...[
                  _ChecklistTile(
                    label: item.stepLabel,
                    meta: item.doneAt == null
                        ? 'Marcado por técnico'
                        : 'Completado ${formatDate(item.doneAt)}',
                  ),
                  if (item != doneItems.last) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class PhaseTimeline extends StatelessWidget {
  final bool isLoading;
  final String? errorText;
  final List<ServicePhaseHistoryModel> items;
  final String Function(DateTime? value) formatDate;
  final String Function(String phase) phaseLabelBuilder;

  const PhaseTimeline({
    super.key,
    required this.isLoading,
    required this.errorText,
    required this.items,
    required this.formatDate,
    required this.phaseLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (isLoading) {
      child = const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if ((errorText ?? '').trim().isNotEmpty) {
      child = _EmptyBlock(
        icon: Icons.error_outline_rounded,
        title: 'No se pudo cargar el historial',
        message: errorText!.trim(),
      );
    } else if (items.isEmpty) {
      child = const _EmptyBlock(
        icon: Icons.timeline_outlined,
        title: 'Sin historial de fases',
        message: 'Esta orden todavía no tiene cambios de fase registrados.',
      );
    } else {
      child = Column(
        children: [
          for (final item in items.take(12)) ...[
            _PhaseTimelineTile(
              title: phaseLabelBuilder(item.phase),
              dateText: formatDate(item.changedAt),
              actor: item.changedBy,
              note: (item.note ?? '').trim().isEmpty ? null : item.note!.trim(),
              isLast: item == items.take(12).last,
            ),
            if (item != items.take(12).last) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return _DetailSurface(
      title: 'Historial de fases',
      icon: Icons.timeline_rounded,
      child: child,
    );
  }
}

class _DetailSurface extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _DetailSurface({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E3EE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFF0C63CE)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF10233F),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;

  const _HeaderBadge({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionMenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final OrderInfoItem item;

  const _InfoPanel({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCaption = (item.caption ?? '').trim().isNotEmpty;

    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FBFE), Color(0xFFF3F8FD)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E4EF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10233F).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFD3E1EE)),
            ),
            child: Icon(item.icon, size: 17, color: const Color(0xFF0C63CE)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.1,
                      color: const Color(0xFF63758C),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: hasCaption ? 4 : 5,
                  child: Text(
                    item.value,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF142B44),
                    ),
                  ),
                ),
                if (hasCaption) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFD5E2EE)),
                      ),
                      child: Text(
                        item.caption!.trim(),
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF5B7088),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageEvidenceTile extends StatelessWidget {
  final OrderEvidenceItem item;

  const _ImageEvidenceTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE6F1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhotoPreview(source: item.url, height: 132),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF16324E),
                      ),
                    ),
                    if ((item.meta ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.meta!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF72849A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _TypePill(label: item.typeLabel),
          ),
        ],
      ),
    );
  }
}

class _MediaEvidenceTile extends StatelessWidget {
  final OrderEvidenceItem item;
  final VoidCallback onTap;

  const _MediaEvidenceTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = item.isVideo
        ? Icons.play_circle_outline_rounded
        : Icons.insert_drive_file_outlined;

    return Material(
      color: const Color(0xFFF8FBFE),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDCE6F1)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDCE6F1)),
                ),
                child: Icon(icon, color: const Color(0xFF145DA0)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF16324E),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TypePill(label: item.typeLabel),
                      ],
                    ),
                    if ((item.meta ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.meta!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF72849A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String label;

  const _TypePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF145DA0),
        ),
      ),
    );
  }
}

class _NoteTimelineTile extends StatelessWidget {
  final OrderNoteEntry entry;

  const _NoteTimelineTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: const Color(0xFF1B3048),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.meta,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF72849A),
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
  final String meta;

  const _ChecklistTile({required this.label, required this.meta});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FBF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9EADF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFDDF4E6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: Color(0xFF18794E),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF16324E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  meta,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF61758B),
                    fontWeight: FontWeight.w700,
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

class _PhaseTimelineTile extends StatelessWidget {
  final String title;
  final String dateText;
  final String actor;
  final String? note;
  final bool isLast;

  const _PhaseTimelineTile({
    required this.title,
    required this.dateText,
    required this.actor,
    required this.note,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF0C63CE),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 64,
                margin: const EdgeInsets.symmetric(vertical: 2),
                color: const Color(0xFFD7E3EF),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FBFD),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2EAF3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF10233F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$actor · $dateText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF72849A),
                  ),
                ),
                if ((note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    note!.trim(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1B3048),
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1EAF4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDCE6F1)),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF6A7B8F)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A2F49),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64758B),
                    height: 1.35,
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