import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/safe_url_launcher.dart';

class MapPreviewCard extends StatelessWidget {
  final double latitude;
  final double longitude;

  final double height;

  const MapPreviewCard({
    super.key,
    required this.latitude,
    required this.longitude,
    this.height = 100,
  });

  static const String _googleStaticMapsApiKey = String.fromEnvironment(
    'GOOGLE_STATIC_MAPS_API_KEY',
    defaultValue: '',
  );

  Uri _googleMapsSearchUri() {
    final q = Uri.encodeQueryComponent('$latitude,$longitude');
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  }

  Uri _googleStaticMapUri() {
    final center = '$latitude,$longitude';
    final base = StringBuffer(
      'https://maps.googleapis.com/maps/api/staticmap?center=$center'
      '&zoom=15&size=600x300&scale=2&maptype=roadmap'
      '&markers=color:red%7C$center',
    );

    if (_googleStaticMapsApiKey.trim().isNotEmpty) {
      base.write('&key=${Uri.encodeQueryComponent(_googleStaticMapsApiKey)}');
    }

    return Uri.parse(base.toString());
  }

  Uri _osmStaticMapUri() {
    // Public static map provider without API key.
    // Equivalent to a static preview (center + marker).
    final center = '$latitude,$longitude';
    final q = Uri(
      scheme: 'https',
      host: 'staticmap.openstreetmap.de',
      path: '/staticmap.php',
      queryParameters: {
        'center': center,
        'zoom': '15',
        'size': '600x300',
        'maptype': 'mapnik',
        'markers': center,
      },
    );
    return q;
  }

  Future<void> _openMaps(BuildContext context) async {
    final uri = _googleMapsSearchUri();

    await safeOpenUrl(context, uri, copiedMessage: 'Link copiado');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final borderRadius = BorderRadius.circular(14);

    final point = LatLng(latitude, longitude);

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
            onTap: () => _openMaps(context),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: kIsWeb
                  ? Image.network(
                      (_googleStaticMapsApiKey.trim().isNotEmpty
                              ? _googleStaticMapUri()
                              : _osmStaticMapUri())
                          .toString(),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.90),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                            child: Icon(
                              Icons.location_on_outlined,
                              color: scheme.onSurface.withValues(alpha: 0.72),
                              size: 22,
                            ),
                          ),
                        );
                      },
                    )
                  : FlutterMap(
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 15,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'fulltech_app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.location_pin,
                                color: theme.colorScheme.error,
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
