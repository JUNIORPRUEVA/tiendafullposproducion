import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/safe_url_launcher.dart';

import '../operations_models.dart';
import '../../../core/utils/geo_utils.dart';
import 'map_preview.dart';
import 'operations_mobile_widgets.dart';
import 'photo_preview.dart';
import 'service_location_helpers.dart';
import 'status_chip.dart';

class ServiceAgendaCard extends StatelessWidget {
  final ServiceModel service;
  final String subtitle;
  final String? scheduledText;
  final String technicianText;

  final VoidCallback onView;
  final Future<void> Function() onChangeState;
  final VoidCallback? onChangePhase;

  const ServiceAgendaCard({
    super.key,
    required this.service,
    required this.subtitle,
    required this.technicianText,
    required this.onView,
    required this.onChangeState,
    this.onChangePhase,
    this.scheduledText,
  });

  Future<void> _openMaps(BuildContext context) async {
    final location = buildServiceLocationInfo(
      addressOrText: service.customerAddress,
    );
    final uri = location.mapsUri;
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final phone = service.customerPhone.trim();
    if (phone.isEmpty) return;

    final digits = _normalizeWhatsAppNumber(phone);
    if (digits.isEmpty) return;

    final customerName = service.customerName.trim().isEmpty
        ? 'cliente'
        : service.customerName.trim();
    final message = 'Hola $customerName, soy ';
    final uri = Uri.parse(
      'https://wa.me/$digits?text=${Uri.encodeComponent(message)}',
    );
    await safeOpenUrl(
      context,
      uri,
      copiedMessage: 'Enlace de WhatsApp copiado',
    );
  }

  Future<void> _callPhone(BuildContext context) async {
    final phone = service.customerPhone.trim();
    if (phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    await safeOpenUrl(context, uri, copiedMessage: 'Link copiado');
  }

  String _normalizeWhatsAppNumber(String raw) {
    var input = raw.trim();
    if (input.isEmpty) return '';

    final waMeMatch = RegExp(
      r'wa\.me/([0-9]+)',
      caseSensitive: false,
    ).firstMatch(input);
    if (waMeMatch != null) {
      input = waMeMatch.group(1) ?? input;
    }

    input = input.replaceAll(
      RegExp(r'(@c\.us|@s\.whatsapp\.net)$', caseSensitive: false),
      '',
    );

    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('00')) {
      digits = digits.replaceFirst(RegExp(r'^00+'), '');
      if (digits.isEmpty) return '';
    }

    final isDominicanLocal =
        digits.length == 10 && RegExp(r'^(809|829|849)').hasMatch(digits);
    if (isDominicanLocal) return '1$digits';

    if (digits.length == 11 && digits.startsWith('1')) return digits;

    return digits;
  }

  String? _firstPhotoUrlOrPath() {
    bool looksLikeImageUrl(String value) {
      final s = value.trim().toLowerCase();
      return s.endsWith('.png') ||
          s.endsWith('.jpg') ||
          s.endsWith('.jpeg') ||
          s.endsWith('.webp');
    }

    for (final f in service.files) {
      final url = f.fileUrl.trim();
      if (url.isEmpty) continue;
      final type = f.fileType.trim().toLowerCase();
      if (type.startsWith('image/')) return url;
      if (looksLikeImageUrl(url)) return url;
    }
    return null;
  }

  String? _creatorFirstName() {
    final full = service.createdByName.trim();
    if (full.isEmpty) return null;
    final parts = full
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return null;
    return parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    final createdByShort = _creatorFirstName();
    final showTechnicianRow =
        service.assignments.isNotEmpty && technicianText.trim().isNotEmpty;
    final showLocationRow = service.customerAddress.trim().isNotEmpty;
    final isCompactCard = !showTechnicianRow && !showLocationRow;

    final customerName = service.customerName.trim().isEmpty
        ? 'Cliente'
        : service.customerName.trim();

    final location = buildServiceLocationInfo(
      addressOrText: service.customerAddress,
    );

    final point = parseLatLngFromText(service.customerAddress);

    final photo = _firstPhotoUrlOrPath();

    final hasExplicitMapsUrl = RegExp(
      r'https?://',
      caseSensitive: false,
    ).hasMatch(service.customerAddress);

    final hasMapPreview = point != null || hasExplicitMapsUrl;
    final hasPhotoPreview = (photo ?? '').trim().isNotEmpty;

    final hasPhone = service.customerPhone.trim().isNotEmpty;

    const previewHeight = 96.0;

    final statusRaw = effectiveServiceStatusLabel(service);

    final servicePhaseText = effectiveServicePhaseLabel(service);
    final adminPhaseRaw = (service.adminPhase ?? '').trim();
    final phaseText = servicePhaseText != '—'
        ? servicePhaseText
        : (adminPhaseRaw.isNotEmpty ? adminPhaseLabel(adminPhaseRaw) : '—');

    if (!isDesktop) {
      return OrderCard(
        service: service,
        subtitle: subtitle,
        technicianText: technicianText,
        scheduledText: scheduledText,
        statusText: statusRaw,
        phaseText: phaseText,
        createdByShort: createdByShort,
        onView: onView,
        onChangeState: onChangeState,
        onChangePhase: onChangePhase,
        onOpenMaps: showLocationRow && location.isDirectLaunch
            ? () {
                unawaited(_openMaps(context));
              }
            : null,
        onChat: hasPhone
            ? () {
                unawaited(_openWhatsApp(context));
              }
            : null,
        onCall: hasPhone
            ? () {
                unawaited(_callPhone(context));
              }
            : null,
      );
    }

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          isDesktop ? (isCompactCard ? 8 : 10) : (isCompactCard ? 10 : 12),
        ),
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
                    style:
                        (isDesktop
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.titleMedium)
                            ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusChip(status: statusRaw),
                    if (createdByShort != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        createdByShort,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.60),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            SizedBox(height: isCompactCard ? 4 : 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.80),
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: isCompactCard ? 6 : 8),
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 8 : 10,
                    vertical: isDesktop ? 5 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Text(
                    'Fase: $phaseText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface.withValues(alpha: 0.78),
                    ),
                  ),
                ),
                if (onChangePhase != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Cambiar fase',
                    onPressed: onChangePhase,
                    style: IconButton.styleFrom(foregroundColor: scheme.error),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                  ),
                ],
              ],
            ),
            if (showLocationRow)
              Column(
                children: [
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                      const SizedBox(width: 6),
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
                      if (location.isDirectLaunch) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Abrir Maps',
                          onPressed: () => _openMaps(context),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          icon: const Icon(Icons.location_on, size: 18),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            if (hasMapPreview && hasPhotoPreview) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: MapPreview(
                      latitude: point?.latitude,
                      longitude: point?.longitude,
                      mapsUrl: hasExplicitMapsUrl
                          ? location.mapsUri?.toString()
                          : null,
                      height: previewHeight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: PhotoPreview(source: photo!, height: previewHeight),
                  ),
                ],
              ),
            ] else if (hasMapPreview) ...[
              const SizedBox(height: 8),
              MapPreview(
                latitude: point?.latitude,
                longitude: point?.longitude,
                mapsUrl: hasExplicitMapsUrl
                    ? location.mapsUri?.toString()
                    : null,
                height: previewHeight,
              ),
            ] else if (!hasMapPreview && hasPhotoPreview) ...[
              const SizedBox(height: 8),
              PhotoPreview(source: photo!, height: previewHeight),
            ],
            SizedBox(height: isCompactCard ? 4 : 6),
            Builder(
              builder: (context) {
                final pill = Container(
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
                );

                if (!showTechnicianRow) {
                  return Align(alignment: Alignment.centerRight, child: pill);
                }

                return Row(
                  children: [
                    Icon(
                      Icons.engineering_outlined,
                      size: 16,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 6),
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
                    pill,
                  ],
                );
              },
            ),
            if (scheduledText != null && scheduledText!.trim().isNotEmpty) ...[
              SizedBox(height: isCompactCard ? 4 : 6),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 16,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 6),
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
            SizedBox(height: isCompactCard ? 8 : 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => onChangeState(),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Cambiar estado'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Ver'),
                ),
                if (hasPhone) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'WhatsApp',
                    onPressed: () => _openWhatsApp(context),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Llamar',
                    onPressed: () => _callPhone(context),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(Icons.call_outlined, size: 18),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
