import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../operations_models.dart';
import '../../../core/utils/geo_utils.dart';
import 'map_preview_card.dart';
import 'service_location_helpers.dart';
import 'status_chip.dart';

class ServiceAgendaCard extends StatelessWidget {
  final ServiceModel service;
  final String subtitle;
  final String? scheduledText;
  final String technicianText;

  final VoidCallback onView;
  final Future<void> Function() onChangeState;

  const ServiceAgendaCard({
    super.key,
    required this.service,
    required this.subtitle,
    required this.technicianText,
    required this.onView,
    required this.onChangeState,
    this.scheduledText,
  });

  Future<void> _safeLaunch(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {
      // ignore
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace')));
  }

  Future<void> _openMaps(BuildContext context) async {
    final location = buildServiceLocationInfo(
      addressOrText: service.customerAddress,
    );
    final uri = location.mapsUri;
    if (uri == null) return;
    await _safeLaunch(context, uri);
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final phone = service.customerPhone.trim();
    if (phone.isEmpty) return;

    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    await _safeLaunch(context, uri);
  }

  Future<void> _callPhone(BuildContext context) async {
    final phone = service.customerPhone.trim();
    if (phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    await _safeLaunch(context, uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final customerName = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();

    final location = buildServiceLocationInfo(
      addressOrText: service.customerAddress,
    );

    final point = parseLatLngFromText(service.customerAddress);

    final hasPhone = service.customerPhone.trim().isNotEmpty;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    status: service.orderState.isEmpty
                        ? service.status
                        : service.orderState,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.80),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (service.createdByName.trim().isNotEmpty) ...[
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Creado por: ${service.createdByName.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Abrir Maps',
                    onPressed: location.canOpenMaps
                        ? () => _openMaps(context)
                        : null,
                    icon: const Icon(Icons.map_outlined, size: 20),
                  ),
                ],
              ),
              if (point != null) ...[
                const SizedBox(height: 10),
                MapPreviewCard(
                  latitude: point.latitude,
                  longitude: point.longitude,
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.engineering_outlined,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      technicianText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.70,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'P${service.priority}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              if (scheduledText != null &&
                  scheduledText!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scheduledText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => onChangeState(),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Cambiar estado'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Ver'),
                  ),
                  if (hasPhone) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'WhatsApp',
                      onPressed: () => _openWhatsApp(context),
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Llamar',
                      onPressed: () => _callPhone(context),
                      icon: const Icon(Icons.call_outlined, size: 20),
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
