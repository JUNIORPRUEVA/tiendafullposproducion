import 'package:flutter/material.dart';

import '../presentation/tech_operations_filters.dart';

class CompactFilterBar extends StatelessWidget {
  final TechOperationsFilterState state;
  final Map<TechOrderStatusFilter, int> statusCounts;
  final Map<TechOrderPhaseFilter, int> phaseCounts;
  final ValueChanged<TechOrderStatusFilter> onToggleStatus;
  final ValueChanged<TechOrderPhaseFilter> onTogglePhase;
  final VoidCallback onClear;

  const CompactFilterBar({
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E3EE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 14,
                color: Color(0xFF0B6BDE),
              ),
              const SizedBox(width: 4),
              const Text(
                'Filtros',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A2F49),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const _SectionTag(label: 'Estado'),
                      const SizedBox(width: 4),
                      for (final filter in TechOrderStatusFilter.values) ...[
                        _CompactChoiceChip(
                          icon: techOrderStatusIcon(filter),
                          label: techOrderStatusLabel(filter),
                          count: statusCounts[filter] ?? 0,
                          selected: state.statuses.contains(filter),
                          color: techOrderStatusColor(filter),
                          onTap: () => onToggleStatus(filter),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
                ),
              ),
              if (state.hasActiveFilters)
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onClear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F5F8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Color(0xFF526277),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const _SectionTag(label: 'Fase'),
                const SizedBox(width: 4),
                for (final filter in TechOrderPhaseFilter.values) ...[
                  _CompactChoiceChip(
                    icon: techOrderPhaseIcon(filter),
                    label: techOrderPhaseLabel(filter),
                    count: phaseCounts[filter] ?? 0,
                    selected: state.phases.contains(filter),
                    color: techOrderPhaseColor(filter),
                    onTap: () => onTogglePhase(filter),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTag extends StatelessWidget {
  final String label;

  const _SectionTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4D617A),
        ),
      ),
    );
  }
}

class _CompactChoiceChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _CompactChoiceChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: color.withValues(alpha: selected ? 0 : 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              '$label $count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF223247),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
