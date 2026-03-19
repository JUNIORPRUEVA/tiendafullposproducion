import 'package:flutter/material.dart';

import '../presentation/tech_operations_filters.dart';

class CompactHeaderWidget extends StatelessWidget {
  final TechOperationsSummary summary;
  final int visibleCount;
  final VoidCallback onOpenDrawer;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  const CompactHeaderWidget({
    super.key,
    required this.summary,
    required this.visibleCount,
    required this.onOpenDrawer,
    required this.onRefresh,
    required this.isRefreshing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF0F2745), Color(0xFF18436F), Color(0xFF1C5E83)],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF153B66).withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconActionButton(
                icon: Icons.menu_rounded,
                tooltip: 'Menú',
                onTap: onOpenDrawer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Operaciones Técnico',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _IconActionButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Actualizar',
                onTap: onRefresh,
                isLoading: isRefreshing,
              ),
              const SizedBox(width: 8),
              _CompactBadge(
                icon: Icons.layers_rounded,
                label: '$visibleCount visibles',
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _MetricChip(
                  icon: Icons.pending_actions_rounded,
                  label: 'Pend',
                  value: summary.pendingCount,
                  accent: const Color(0xFFFFC857),
                ),
                const SizedBox(width: 6),
                _MetricChip(
                  icon: Icons.autorenew_rounded,
                  label: 'Proceso',
                  value: summary.inProgressCount,
                  accent: const Color(0xFF8DD0FF),
                ),
                const SizedBox(width: 6),
                _MetricChip(
                  icon: Icons.priority_high_rounded,
                  label: 'Urg',
                  value: summary.urgentCount,
                  accent: const Color(0xFFFF9E7A),
                ),
                const SizedBox(width: 6),
                _MetricChip(
                  icon: Icons.electrical_services_rounded,
                  label: 'Alta',
                  value: summary.primaryCount,
                  accent: const Color(0xFF7DF0C5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isLoading;

  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: isLoading ? null : onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _CompactBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CompactBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color accent;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            '$label $value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
