import 'package:flutter/material.dart';

import '../../operations_models.dart';

enum TechAllowedServiceType {
  installation,
  maintenance,
  warranty,
  survey,
  other,
}

String _normalizeKey(String raw) {
  var v = raw.trim().toLowerCase();
  if (v.isEmpty) return '';
  v = v
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');
  v = v.replaceAll(' ', '_').replaceAll('-', '_');
  return v;
}

TechAllowedServiceType techAllowedServiceTypeFrom(ServiceModel service) {
  final key = _normalizeKey(service.serviceType);
  switch (key) {
    case 'installation':
    case 'instalacion':
      return TechAllowedServiceType.installation;
    case 'maintenance':
    case 'mantenimiento':
      return TechAllowedServiceType.maintenance;
    case 'warranty':
    case 'garantia':
      return TechAllowedServiceType.warranty;
    case 'survey':
    case 'levantamiento':
      return TechAllowedServiceType.survey;
    default:
      return TechAllowedServiceType.other;
  }
}

String techServiceTypeBadgeLabel(TechAllowedServiceType type) {
  switch (type) {
    case TechAllowedServiceType.installation:
      return 'INSTALACIÓN';
    case TechAllowedServiceType.maintenance:
      return 'MANTENIMIENTO';
    case TechAllowedServiceType.warranty:
      return 'GARANTÍA';
    case TechAllowedServiceType.survey:
      return 'LEVANTAMIENTO';
    case TechAllowedServiceType.other:
      return 'SERVICIO';
  }
}

String techServiceTypeTitle(ServiceModel service) {
  String typeLabel(String raw) {
    switch (_normalizeKey(raw)) {
      case 'installation':
      case 'instalacion':
        return 'Instalación';
      case 'maintenance':
      case 'mantenimiento':
        return 'Mantenimiento';
      case 'warranty':
      case 'garantia':
        return 'Garantía';
      case 'survey':
      case 'levantamiento':
        return 'Levantamiento';
      default:
        return raw.trim().isEmpty ? 'Servicio' : raw.trim();
    }
  }

  String categoryLabel(String raw) {
    switch (_normalizeKey(raw)) {
      case 'cameras':
      case 'camara':
      case 'camaras':
        return 'Cámaras';
      case 'gate_motor':
      case 'motor_puerton':
      case 'motores_puertones':
        return 'Motor de portón';
      case 'alarm':
      case 'alarma':
        return 'Alarma';
      case 'electric_fence':
      case 'cerco_electrico':
        return 'Cerco eléctrico';
      case 'intercom':
      case 'intercomunicador':
        return 'Intercomunicador';
      case 'pos':
        return 'POS';
      default:
        return raw.trim();
    }
  }

  final t = typeLabel(service.serviceType);
  final c = categoryLabel(service.category);
  return c.isEmpty ? t : '$t - $c';
}

enum TechServiceStatusBadge { pending, inProgress, completed }

TechServiceStatusBadge techStatusBadgeFrom(ServiceStatus status) {
  switch (status) {
    case ServiceStatus.inProgress:
    case ServiceStatus.warranty:
      return TechServiceStatusBadge.inProgress;
    case ServiceStatus.completed:
    case ServiceStatus.closed:
    case ServiceStatus.cancelled:
      return TechServiceStatusBadge.completed;
    case ServiceStatus.reserved:
    case ServiceStatus.scheduled:
    case ServiceStatus.survey:
    case ServiceStatus.unknown:
      return TechServiceStatusBadge.pending;
  }
}

String techStatusBadgeLabel(TechServiceStatusBadge badge) {
  switch (badge) {
    case TechServiceStatusBadge.pending:
      return 'Pendiente';
    case TechServiceStatusBadge.inProgress:
      return 'En progreso';
    case TechServiceStatusBadge.completed:
      return 'Finalizado';
  }
}

class ServiceCardWidget extends StatelessWidget {
  final ServiceModel service;
  final TechAllowedServiceType type;
  final TechServiceStatusBadge status;
  final String scheduledDateLabel;
  final String orderIdLabel;
  final String assignedTechnicianLabel;
  final bool canManage;
  final VoidCallback onOpenDetails;
  final VoidCallback onManageService;
  final VoidCallback? onOpenLocation;

  const ServiceCardWidget({
    super.key,
    required this.service,
    required this.type,
    required this.status,
    required this.scheduledDateLabel,
    required this.orderIdLabel,
    required this.assignedTechnicianLabel,
    this.canManage = true,
    required this.onOpenDetails,
    required this.onManageService,
    this.onOpenLocation,
  });

  Color _badgeBg(ColorScheme cs, {required bool primary}) {
    return primary ? cs.primaryContainer : cs.tertiaryContainer;
  }

  Color _badgeFg(ColorScheme cs, {required bool primary}) {
    return primary ? cs.onPrimaryContainer : cs.onTertiaryContainer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final customer = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();

    final typeTitle = techServiceTypeTitle(service);

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: InkWell(
        onTap: onOpenDetails,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
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
                          customer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          typeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Badge(
                        label: techServiceTypeBadgeLabel(type),
                        background: _badgeBg(cs, primary: true),
                        foreground: _badgeFg(cs, primary: true),
                      ),
                      const SizedBox(height: 6),
                      _Badge(
                        label: techStatusBadgeLabel(status),
                        background: _badgeBg(cs, primary: false),
                        foreground: _badgeFg(cs, primary: false),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _InfoRow(label: 'Fecha:', value: scheduledDateLabel),
              const SizedBox(height: 4),
              _InfoRow(label: 'Orden:', value: orderIdLabel),
              const SizedBox(height: 4),
              _InfoRow(label: 'Técnico:', value: assignedTechnicianLabel),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onPressed: canManage ? onManageService : null,
                      icon: const Icon(Icons.build_outlined, size: 18),
                      label: const Text('Gestionar'),
                    ),
                  ),
                  if (onOpenLocation != null) ...[
                    const SizedBox(width: 10),
                    IconButton(
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: 'Ubicación (GPS)',
                      onPressed: onOpenLocation,
                      icon: const Icon(Icons.location_on_outlined),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: foreground,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value.trim().isEmpty ? '—' : value.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
