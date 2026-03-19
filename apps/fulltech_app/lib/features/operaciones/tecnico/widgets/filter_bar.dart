import 'package:flutter/material.dart';

import '../presentation/tech_operations_filters.dart';

class FilterBar extends StatelessWidget {
  final TechOperationsFilterState state;
  final Map<TechOrderStatusFilter, int> statusCounts;
  final Map<TechOrderPhaseFilter, int> phaseCounts;
  final ValueChanged<TechOrderStatusFilter> onToggleStatus;
  final ValueChanged<TechOrderPhaseFilter> onTogglePhase;
  final VoidCallback onClear;

  const FilterBar({
    super.key,
    required this.state,
    required this.statusCounts,
    required this.phaseCounts,
    required this.onToggleStatus,
    required this.onTogglePhase,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF0B6BDE)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtros operativos',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF10233F),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Combina estado y fase para ver solo lo que importa.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF5B6B82),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.hasActiveFilters)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Limpiar'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SectionLabel(label: 'Estado'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final filter in TechOrderStatusFilter.values)
                _FilterChipCard(
                  icon: techOrderStatusIcon(filter),
                  label: techOrderStatusLabel(filter),
                  count: statusCounts[filter] ?? 0,
                  selected: state.statuses.contains(filter),
                  color: techOrderStatusColor(filter),
                  onTap: () => onToggleStatus(filter),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SectionLabel(label: 'Fase'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final filter in TechOrderPhaseFilter.values)
                _FilterChipCard(
                  icon: techOrderPhaseIcon(filter),
                  label: techOrderPhaseLabel(filter),
                  count: phaseCounts[filter] ?? 0,
                  selected: state.phases.contains(filter),
                  color: techOrderPhaseColor(filter),
                  onTap: () => onTogglePhase(filter),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: const Color(0xFF36455C),
      ),
    );
  }
}

class _FilterChipCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChipCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      avatar: Icon(icon, size: 18, color: selected ? Colors.white : color),
      label: Text('$label  $count'),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : const Color(0xFF24364D),
      ),
      side: BorderSide(color: color.withValues(alpha: selected ? 0 : 0.35)),
      backgroundColor: Colors.white,
      selectedColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}
