import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/safe_url_launcher.dart';
import '../../../core/utils/geo_utils.dart';
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

  static final Map<String, LatLng?> _resolvedCache = <String, LatLng?>{};
  static final Map<String, Future<LatLng?>> _inflight =
      <String, Future<LatLng?>>{};

  static bool _inRange(double lat, double lng) {
    if (lat.isNaN || lng.isNaN) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  static LatLng? _tryExtractLatLngFromLatLonFields(String text) {
    final latRaw =
        RegExp(
          r'place:location:latitude"\s+content="(-?\d{1,2}(?:\.\d+)?)"',
          caseSensitive: false,
        ).firstMatch(text)?.group(1) ??
        RegExp(
          r'\blatitude\b\s*[:=]\s*"?(-?\d{1,2}(?:\.\d+)?)"?',
          caseSensitive: false,
        ).firstMatch(text)?.group(1);

    final lngRaw =
        RegExp(
          r'place:location:longitude"\s+content="(-?\d{1,3}(?:\.\d+)?)"',
          caseSensitive: false,
        ).firstMatch(text)?.group(1) ??
        RegExp(
          r'\blongitude\b\s*[:=]\s*"?(-?\d{1,3}(?:\.\d+)?)"?',
          caseSensitive: false,
        ).firstMatch(text)?.group(1) ??
        RegExp(
          r'\blon\b\s*[:=]\s*"?(-?\d{1,3}(?:\.\d+)?)"?',
          caseSensitive: false,
        ).firstMatch(text)?.group(1);

    final lat = double.tryParse(latRaw ?? '');
    final lng = double.tryParse(lngRaw ?? '');
    if (lat == null || lng == null) return null;
    if (!_inRange(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  static LatLng? _tryExtractLatLngByRegex(String text) {
    final patterns = <RegExp>[
      RegExp(r'@\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*,'),
      RegExp(r'center=(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)'),
      RegExp(r'll=(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)'),
      RegExp(r'q=(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)'),
      RegExp(r'!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)'),
      RegExp(r'(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)'),
    ];

    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m == null) continue;
      final lat = double.tryParse(m.group(1) ?? '');
      final lng = double.tryParse(m.group(2) ?? '');
      if (lat != null && lng != null && _inRange(lat, lng)) {
        return LatLng(lat, lng);
      }
    }

    return null;
  }

  static Future<LatLng?> _resolveLatLngFromUrl(String url) async {
    final key = url.trim();
    if (key.isEmpty) return null;

    if (_resolvedCache.containsKey(key)) {
      return _resolvedCache[key];
    }

    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = () async {
      try {
        final uri = Uri.tryParse(key);
        if (uri == null) return null;

        final dio = Dio(
          BaseOptions(
            followRedirects: true,
            maxRedirects: 8,
            connectTimeout: const Duration(seconds: 6),
            sendTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 8),
            responseType: ResponseType.plain,
            validateStatus: (s) => s != null && s >= 200 && s < 500,
          ),
        );

        final response = await dio.getUri(uri);

        final resolvedUrl = response.realUri.toString();
        final fromResolvedUrl = parseLatLngFromText(resolvedUrl);
        if (fromResolvedUrl != null) return fromResolvedUrl;

        final fromResolvedUrlRegex = _tryExtractLatLngByRegex(resolvedUrl);
        if (fromResolvedUrlRegex != null) return fromResolvedUrlRegex;

        final fromResolvedFields = _tryExtractLatLngFromLatLonFields(
          resolvedUrl,
        );
        if (fromResolvedFields != null) return fromResolvedFields;

        final body = response.data?.toString() ?? '';
        final fromBodyRegex = _tryExtractLatLngByRegex(body);
        if (fromBodyRegex != null) return fromBodyRegex;

        final fromBodyFields = _tryExtractLatLngFromLatLonFields(body);
        if (fromBodyFields != null) return fromBodyFields;

        return null;
      } catch (_) {
        return null;
      }
    }();

    _inflight[key] = future;
    final result = await future;
    _inflight.remove(key);
    _resolvedCache[key] = result;
    return result;
  }

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

    final parsedFromMaps = _hasCoords
        ? null
        : parseLatLngFromText((mapsUrl ?? '').trim());
    final effectiveLat = latitude ?? parsedFromMaps?.latitude;
    final effectiveLng = longitude ?? parsedFromMaps?.longitude;
    final canRenderStatic = effectiveLat != null && effectiveLng != null;

    if (canRenderStatic) {
      return MapPreviewCard(
        latitude: effectiveLat!,
        longitude: effectiveLng!,
        height: height,
      );
    }

    final borderRadius = BorderRadius.circular(14);

    Future<Widget> resolvedPreview() async {
      final raw = (mapsUrl ?? '').trim();
      final point = await _resolveLatLngFromUrl(raw);
      if (point == null) return const SizedBox.shrink();
      return MapPreviewCard(
        latitude: point.latitude,
        longitude: point.longitude,
        height: height,
      );
    }

    final fallback = Container(
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

    final raw = (mapsUrl ?? '').trim();
    final uri = Uri.tryParse(raw);
    final shouldResolve =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (!shouldResolve) return fallback;

    return FutureBuilder<Widget>(
      future: resolvedPreview(),
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved != null && resolved is! SizedBox) return resolved;
        return fallback;
      },
    );
  }
}
