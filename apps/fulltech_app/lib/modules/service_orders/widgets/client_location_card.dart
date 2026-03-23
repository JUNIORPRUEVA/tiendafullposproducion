import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../../clientes/client_location_utils.dart';
import '../../clientes/cliente_model.dart';

Uri? buildClientNavigationUri(
  ClientLocationPreview preview,
  String? locationUrl,
) {
  if (preview.hasCoordinates) {
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${preview.latitude},${preview.longitude}',
    );
  }

  final normalized = normalizeClientLocationUrl(locationUrl);
  if (normalized.isEmpty) return null;
  return Uri.tryParse(normalized);
}

class ClientLocationCard extends ConsumerWidget {
  const ClientLocationCard({
    super.key,
    required this.client,
    this.title = 'Ubicacion del cliente',
    this.compact = false,
  });

  final ClienteModel? client;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationUrl = client?.locationUrl;
    final normalizedUrl = normalizeClientLocationUrl(locationUrl);
    final directPreview = parseClientLocationPreview(normalizedUrl);

    if (normalizedUrl.isEmpty && !directPreview.hasCoordinates) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<ClientLocationPreview>(
              future: resolveClientLocationPreview(
                normalizedUrl,
                dio: ref.read(dioProvider),
              ),
              initialData: directPreview,
              builder: (context, snapshot) {
                final preview = snapshot.data ?? directPreview;
                final navigationUri = buildClientNavigationUri(
                  preview,
                  normalizedUrl,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (preview.hasCoordinates)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: compact ? 180 : 220,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(
                                preview.latitude!,
                                preview.longitude!,
                              ),
                              initialZoom: 15,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.fulltech.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                      preview.latitude!,
                                      preview.longitude!,
                                    ),
                                    width: 40,
                                    height: 40,
                                    child: Icon(
                                      Icons.location_pin,
                                      color: theme.colorScheme.error,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (snapshot.connectionState ==
                        ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'La ubicacion esta vinculada, pero no se pudieron resolver coordenadas para pintar el mapa.',
                        ),
                      ),
                    if (preview.hasCoordinates) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${preview.latitude!.toStringAsFixed(6)}, ${preview.longitude!.toStringAsFixed(6)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (navigationUri != null) ...[
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => safeOpenUrl(context, navigationUri),
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text('Ir a la ubicacion'),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
