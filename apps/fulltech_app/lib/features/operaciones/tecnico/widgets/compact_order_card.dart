import 'package:flutter/material.dart';

import '../../operations_models.dart';
import '../presentation/tech_operations_filters.dart';

class CompactOrderCard extends StatelessWidget {
  final ServiceModel service;
  final String? locationLabel;
  final bool canManage;
  final VoidCallback onOpenDetails;
  final VoidCallback onManageService;
  final VoidCallback? onOpenLocation;

  const CompactOrderCard({
    super.key,
    required this.service,
    required this.locationLabel,
    required this.canManage,
    required this.onOpenDetails,
    required this.onManageService,
    this.onOpenLocation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = techOrderStatusFrom(service);
    final phase = techOrderPhaseFrom(service);
    final accent = phase == null
        ? const Color(0xFF355070)
        : techOrderPhaseColor(phase);
    final customerName = service.customerName.trim().isEmpty
        ? 'Cliente sin nombre'
        : service.customerName.trim();
    final typeLabel = phase == null ? 'Servicio' : techOrderPhaseLabel(phase);
    final dateLabel = _formatDate(service);
    final orderLabel = service.orderLabel.trim();
    final metaRight = orderLabel.isNotEmpty ? orderLabel : dateLabel;

    return RepaintBoundary(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpenDetails,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.16)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.035),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF10233F),
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      metaRight,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF63758A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _DenseBadge(
                            icon: phase == null
                                ? Icons.miscellaneous_services_rounded
                                : techOrderPhaseIcon(phase),
                            label: typeLabel,
                            color: accent,
                            filled: isPrimaryTechOrder(service),
                          ),
                          _DenseBadge(
                            icon: techOrderStatusIcon(status),
                            label: techOrderStatusLabel(status),
                            color: techOrderStatusColor(status),
                          ),
                          if (isUrgentTechOrder(service))
                            const _DenseBadge(
                              icon: Icons.priority_high_rounded,
                              label: 'Urgente',
                              color: Color(0xFFBA4A00),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 30,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: canManage ? onManageService : null,
                        child: const Text(
                          'Gestionar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 12,
                      color: const Color(0xFF71859A),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: const Color(0xFF5D7085),
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                    if (locationLabel != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 12,
                              color: const Color(0xFF71859A),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                locationLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: const Color(0xFF5D7085),
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                ),
                              ),
                            ),
                            if (onOpenLocation != null) ...[
                              const SizedBox(width: 2),
                              InkWell(
                                onTap: onOpenLocation,
                                borderRadius: BorderRadius.circular(999),
                                child: const Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.open_in_new_rounded,
                                    size: 12,
                                    color: Color(0xFF71859A),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(ServiceModel service) {
    final value = (service.scheduledStart ?? service.scheduledEnd)?.toLocal();
    if (value == null) return 'Sin fecha';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$day/$month · $hour:$minute $suffix';
  }
}

class _DenseBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;

  const _DenseBadge({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = filled ? color : color.withValues(alpha: 0.1);
    final foreground = filled ? Colors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: foreground,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
