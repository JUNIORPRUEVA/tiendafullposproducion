import 'package:flutter/material.dart';

import '../../operations_models.dart';
import '../presentation/tech_operations_filters.dart';

class OrderCard extends StatelessWidget {
  final ServiceModel service;
  final String? locationLabel;
  final bool canManage;
  final VoidCallback onOpenDetails;
  final VoidCallback onManageService;
  final VoidCallback? onOpenLocation;

  const OrderCard({
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
    final cs = theme.colorScheme;
    final phase = techOrderPhaseFrom(service);
    final status = techOrderStatusFrom(service);
    final accent = phase == null ? cs.primary : techOrderPhaseColor(phase);
    final isPrimary = isPrimaryTechOrder(service);
    final isUrgent = isUrgentTechOrder(service);
    final customerName = service.customerName.trim().isEmpty
        ? 'Cliente sin nombre'
        : service.customerName.trim();
    final orderNumber = service.orderLabel.trim();
    final serviceHeadline = techServiceHeadline(service);
    final assignedTech = service.assignments
        .map((assignment) => assignment.userName.trim())
        .where((name) => name.isNotEmpty)
        .join(', ');

    final infoChips = <_MetaDataChipData>[
      if (_formatSchedule(service) case final schedule?
          when schedule.isNotEmpty)
        _MetaDataChipData(icon: Icons.calendar_month_rounded, label: schedule),
      if (orderNumber.isNotEmpty)
        _MetaDataChipData(
          icon: Icons.confirmation_number_outlined,
          label: orderNumber,
        ),
      if (assignedTech.isNotEmpty)
        _MetaDataChipData(
          icon: Icons.person_outline_rounded,
          label: assignedTech,
        ),
    ];

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Material(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onOpenDetails,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: accent.withValues(alpha: isPrimary ? 0.28 : 0.16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: isPrimary ? 0.11 : 0.06),
                    Colors.white,
                    Colors.white,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Pill(
                                    icon: phase == null
                                        ? Icons.miscellaneous_services_rounded
                                        : techOrderPhaseIcon(phase),
                                    label: phase == null
                                        ? 'Servicio'
                                        : techOrderPhaseLabel(phase),
                                    background: accent.withValues(
                                      alpha: isPrimary ? 0.16 : 0.1,
                                    ),
                                    foreground: accent,
                                  ),
                                  _Pill(
                                    icon: techOrderStatusIcon(status),
                                    label: techOrderStatusLabel(status),
                                    background: techOrderStatusColor(
                                      status,
                                    ).withValues(alpha: 0.14),
                                    foreground: techOrderStatusColor(status),
                                  ),
                                  if (isUrgent)
                                    const _Pill(
                                      icon: Icons.priority_high_rounded,
                                      label: 'Urgente',
                                      background: Color(0xFFFFEFE3),
                                      foreground: Color(0xFFBA4A00),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                customerName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF0E2038),
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                serviceHeadline,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: const Color(0xFF49607E),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isPrimary
                                ? Icons.electrical_services_rounded
                                : Icons.handyman_rounded,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    if (locationLabel != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8FC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              size: 20,
                              color: accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                locationLabel!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF20344D),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (onOpenLocation != null) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: onOpenLocation,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.map_outlined,
                                    size: 18,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (infoChips.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final chip in infoChips)
                            _MetaDataChip(data: chip),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: canManage ? onManageService : null,
                            icon: const Icon(Icons.build_circle_outlined),
                            label: const Text('Gestionar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF20344D),
                            side: BorderSide(
                              color: accent.withValues(alpha: 0.26),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: onOpenDetails,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Ver orden'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _formatSchedule(ServiceModel service) {
    final scheduled = service.scheduledStart ?? service.scheduledEnd;
    if (scheduled == null) return null;

    final value = scheduled.toLocal();
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$day/$month/$year • $hour:$minute $suffix';
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
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
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: foreground,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaDataChipData {
  final IconData icon;
  final String label;

  const _MetaDataChipData({required this.icon, required this.label});
}

class _MetaDataChip extends StatelessWidget {
  final _MetaDataChipData data;

  const _MetaDataChip({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 16, color: const Color(0xFF5B6B82)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              data.label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
