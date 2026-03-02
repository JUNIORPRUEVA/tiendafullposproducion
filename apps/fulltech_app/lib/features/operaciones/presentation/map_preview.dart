import 'package:flutter/material.dart';

import '../../../core/utils/safe_url_launcher.dart';
import 'map_preview_card.dart';

class MapPreview extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final String? mapsUrl;
  final double height;

  const MapPreview({
    super.key,
    this.latitude,
    this.longitude,
    this.mapsUrl,
    this.height = 120,
  });

  bool get _hasCoords => latitude != null && longitude != null;

  Uri? _targetUri() {
    if (_hasCoords) {
      final q = Uri.encodeQueryComponent('${latitude!},${longitude!}');
      return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }

    final raw = (mapsUrl ?? '').trim();
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final target = _targetUri();
    if (target == null) return const SizedBox.shrink();

    if (_hasCoords) {
      return MapPreviewCard(
        latitude: latitude!,
        longitude: longitude!,
        height: height,
      );
    }

    final borderRadius = BorderRadius.circular(14);

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: InkWell(
            onTap: () =>
                safeOpenUrl(context, target, copiedMessage: 'Link copiado'),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ver en Maps',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
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
}
