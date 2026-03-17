import 'package:flutter/material.dart';

import '../../operations_models.dart';

class DynamicChecklistSummaryCard extends StatelessWidget {
  final List<ServiceChecklistTemplateModel> templates;
  final VoidCallback? onOpen;
  final String buttonLabel;

  const DynamicChecklistSummaryCard({
    super.key,
    required this.templates,
    required this.onOpen,
    this.buttonLabel = 'Checklist',
  });

  int get _requiredTotal => templates.fold<int>(
        0,
        (sum, template) =>
            sum + template.items.where((item) => item.isRequired).length,
      );

  int get _requiredCompleted => templates.fold<int>(
        0,
        (sum, template) =>
            sum +
            template.items
                .where((item) => item.isRequired && item.isChecked)
                .length,
      );

  Iterable<ServiceChecklistSectionType> get _sectionTypes => const [
        ServiceChecklistSectionType.herramientas,
        ServiceChecklistSectionType.productos,
        ServiceChecklistSectionType.instalacion,
      ];

  ({int completed, int total}) _sectionStats(ServiceChecklistSectionType type) {
    final items = templates
        .where((template) => template.type == type)
        .expand((template) => template.items)
        .where((item) => item.isRequired)
        .toList(growable: false);
    final completed = items.where((item) => item.isChecked).length;
    return (completed: completed, total: items.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = _requiredTotal;
    final completed = _requiredCompleted;
    final ratio = total == 0 ? 0.0 : completed / total;
    final percent = (ratio * 100).round();
    final sectionStats = _sectionTypes
      .map((type) => (type: type, stats: _sectionStats(type)))
      .where((entry) => entry.stats.total > 0)
      .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
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
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: total == 0
                      ? cs.surfaceContainerHighest
                      : (completed == total
                            ? Colors.green.withValues(alpha: 0.14)
                            : cs.primary.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  completed == total && total > 0
                      ? Icons.task_alt_rounded
                      : Icons.checklist_rtl_outlined,
                  color: completed == total && total > 0
                      ? Colors.green
                      : cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CHECKLIST',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      total == 0
                          ? 'No hay checklist configurado para esta etapa.'
                          : '$completed de $total obligatorios listos',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_full_rounded),
                label: Text(buttonLabel),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: ratio == 0 ? 0 : ratio.clamp(0.0, 1.0),
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                completed == total && total > 0 ? Colors.green : cs.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '$percent%',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  completed == total && total > 0
                      ? 'Checklist completo. Ya puedes avanzar el estado con seguridad.'
                      : 'Abre el detalle para completar herramientas, productos e instalación.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (sectionStats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sectionStats
                  .map(
                    (entry) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: entry.stats.completed == entry.stats.total
                            ? Colors.green.withValues(alpha: 0.10)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        entry.stats.completed == entry.stats.total
                            ? '${serviceChecklistSectionTypeLabel(entry.type)} completa'
                            : '${serviceChecklistSectionTypeLabel(entry.type)} ${entry.stats.completed}/${entry.stats.total}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: entry.stats.completed == entry.stats.total
                              ? Colors.green.shade700
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class DynamicChecklistSheet extends StatelessWidget {
  final List<ServiceChecklistTemplateModel> templates;
  final Future<void> Function(String itemId, bool checked)? onChanged;
  final Future<void> Function()? onChecklistCompleted;
  final bool readOnly;
  final bool busy;
  final String title;

  const DynamicChecklistSheet({
    super.key,
    required this.templates,
    required this.onChanged,
    required this.onChecklistCompleted,
    required this.readOnly,
    required this.busy,
    this.title = 'Checklist del servicio',
  });

  static Future<void> show(
    BuildContext context, {
    required List<ServiceChecklistTemplateModel> templates,
    required Future<void> Function(String itemId, bool checked)? onChanged,
    required Future<void> Function()? onChecklistCompleted,
    required bool readOnly,
    required bool busy,
    String title = 'Checklist del servicio',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicChecklistSheet(
        templates: templates,
        onChanged: onChanged,
        onChecklistCompleted: onChecklistCompleted,
        readOnly: readOnly,
        busy: busy,
        title: title,
      ),
    );
  }

  int get _requiredTotal => templates.fold<int>(
        0,
        (sum, template) =>
            sum + template.items.where((item) => item.isRequired).length,
      );

  int get _requiredCompleted => templates.fold<int>(
        0,
        (sum, template) =>
            sum +
            template.items
                .where((item) => item.isRequired && item.isChecked)
                .length,
      );

  bool get _complete => _requiredTotal > 0 && _requiredCompleted == _requiredTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = _requiredTotal == 0 ? 0.0 : _requiredCompleted / _requiredTotal;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _requiredTotal == 0
                                ? 'No hay checklist activo para esta etapa.'
                                : '$_requiredCompleted/$_requiredTotal obligatorios completados',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (busy)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: ratio == 0 ? 0 : ratio.clamp(0.0, 1.0),
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _complete ? Colors.green : cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: templates.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No hay checklist configurado para esta combinación de categoría y etapa.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == templates.length - 1 ? 0 : 14,
                        ),
                        child: _TemplateSectionCard(
                          template: template,
                          readOnly: readOnly,
                          onChanged: onChanged,
                        ),
                      );
                    },
                  ),
          ),
          if (_complete && onChecklistCompleted != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onChecklistCompleted,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Checklist completo, sugerir cambio de estado'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplateSectionCard extends StatelessWidget {
  final ServiceChecklistTemplateModel template;
  final Future<void> Function(String itemId, bool checked)? onChanged;
  final bool readOnly;

  const _TemplateSectionCard({
    required this.template,
    required this.onChanged,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final total = template.items.where((item) => item.isRequired).length;
    final completed = template.items
        .where((item) => item.isRequired && item.isChecked)
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceChecklistSectionTypeLabel(template.type),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$completed/$total',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...template.items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == template.items.length - 1 ? 0 : 10,
              ),
              child: _ChecklistRow(
                item: item,
                readOnly: readOnly,
                onChanged: onChanged,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final ServiceChecklistItemModel item;
  final Future<void> Function(String itemId, bool checked)? onChanged;
  final bool readOnly;

  const _ChecklistRow({
    required this.item,
    required this.onChanged,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final checked = item.isChecked;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: checked
            ? Colors.green.withValues(alpha: 0.10)
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: checked
              ? Colors.green.withValues(alpha: 0.24)
              : cs.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: readOnly || onChanged == null
            ? null
            : () => onChanged!(item.id, !checked),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: checked ? Colors.green : cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: checked ? Colors.green : cs.outline,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  checked ? Icons.check_rounded : Icons.circle_outlined,
                  size: 18,
                  color: checked ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: checked ? Colors.green.shade800 : cs.onSurface,
                  ),
                ),
              ),
              if (!item.isRequired)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Opcional',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
