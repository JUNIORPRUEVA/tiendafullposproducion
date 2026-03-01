import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/api_exception.dart';
import '../../core/utils/geo_utils.dart';
import 'data/operations_repository.dart';
import 'operations_models.dart';

class OperacionesMapaClientesScreen extends ConsumerStatefulWidget {
  const OperacionesMapaClientesScreen({super.key});

  @override
  ConsumerState<OperacionesMapaClientesScreen> createState() =>
      _OperacionesMapaClientesScreenState();
}

class _ServicePoint {
  final ServiceModel service;
  final LatLng point;

  const _ServicePoint(this.service, this.point);
}

class _OperacionesMapaClientesScreenState
    extends ConsumerState<OperacionesMapaClientesScreen> {
  final _mapController = MapController();
  late Future<List<_ServicePoint>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadPoints();
  }

  Future<List<_ServicePoint>> _loadPoints() async {
    final repo = ref.read(operationsRepositoryProvider);

    const pageSize = 200;
    var page = 1;
    final all = <ServiceModel>[];

    while (true) {
      final res = await repo.listServices(page: page, pageSize: pageSize);
      all.addAll(res.items);

      final done = all.length >= res.total || res.items.isEmpty;
      if (done) break;

      page += 1;
      if (page > 50) break; // safety: avoid infinite paging
    }

    final points = <_ServicePoint>[];
    for (final s in all) {
      final p = parseLatLngFromText(s.customerAddress);
      if (p == null) continue;
      points.add(_ServicePoint(s, p));
    }
    return points;
  }

  Future<void> _openInMaps(LatLng point) async {
    final url = Uri.parse(buildGoogleMapsSearchUrl(point));
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _showServiceDialog(_ServicePoint item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          item.service.customerName.isEmpty
              ? 'Ubicación'
              : item.service.customerName,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.service.title.trim().isNotEmpty)
              Text(
                item.service.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (item.service.customerPhone.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Tel: ${item.service.customerPhone}'),
            ],
            const SizedBox(height: 10),
            Text('GPS: ${formatLatLng(item.point)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await _openInMaps(item.point);
            },
            icon: const Icon(Icons.near_me_outlined),
            label: const Text('Abrir en Maps'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mapa clientes')),
      body: FutureBuilder<List<_ServicePoint>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            final e = snap.error;
            final message = e is ApiException
                ? e.message
                : 'No se pudo cargar el mapa';
            return Center(child: Text(message));
          }

          final points = snap.data ?? const <_ServicePoint>[];
          if (points.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Aún no hay ubicaciones con GPS guardadas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            );
          }

          final initial = points.first.point;

          final markers = points
              .map(
                (item) => Marker(
                  width: 48,
                  height: 48,
                  point: item.point,
                  child: GestureDetector(
                    onTap: () => _showServiceDialog(item),
                    child: Tooltip(
                      message: item.service.customerName.trim().isEmpty
                          ? item.service.customerPhone
                          : item.service.customerName,
                      child: Icon(
                        Icons.location_on,
                        color: scheme.primary,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              )
              .toList();

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: initial, initialZoom: 12),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'fulltech_app',
              ),
              MarkerLayer(markers: markers),
            ],
          );
        },
      ),
    );
  }
}
