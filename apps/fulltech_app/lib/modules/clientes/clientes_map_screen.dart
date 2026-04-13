import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/cache/fulltech_map_tile_cache.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/routing/routes.dart';
import '../service_orders/application/service_orders_list_controller.dart';
import '../service_orders/service_order_models.dart';
import 'application/clientes_controller.dart';
import 'client_location_utils.dart';
import 'cliente_model.dart';

class ClientesMapScreen extends ConsumerStatefulWidget {
  const ClientesMapScreen({super.key});

  @override
  ConsumerState<ClientesMapScreen> createState() => _ClientesMapScreenState();
}

class _ClientesMapScreenState extends ConsumerState<ClientesMapScreen> {
  Map<String, ClientLocationPreview> _locationsByClientId = const {};
  bool _resolvingLocations = false;
  String _locationSignature = '';
  String _tileWarmSignature = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final clientsState = ref.read(clientesControllerProvider);
    final ordersState = ref.read(serviceOrdersListControllerProvider);
    final pending = <Future<void>>[];

    if (clientsState.items.isEmpty && !clientsState.loading) {
      pending.add(ref.read(clientesControllerProvider.notifier).refresh());
    }
    if (ordersState.items.isEmpty && !ordersState.loading) {
      pending.add(
        ref.read(serviceOrdersListControllerProvider.notifier).refresh(),
      );
    }

    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
    if (!mounted) return;
    await _resolveLocations(force: true);
  }

  Future<void> _resolveLocations({bool force = false}) async {
    final clients = ref.read(clientesControllerProvider).items;
    final signature = clients
        .map(
          (client) =>
              '${client.id}|${client.locationUrl ?? ''}|${client.latitude ?? ''}|${client.longitude ?? ''}',
        )
        .join('||');

    if (!force && signature == _locationSignature) return;

    setState(() => _resolvingLocations = true);
    final dio = ref.read(dioProvider);

    try {
      final entries = await Future.wait(
        clients.map((client) async {
          if (client.latitude != null &&
              client.longitude != null &&
              client.latitude!.isFinite &&
              client.longitude!.isFinite) {
            return MapEntry(
              client.id,
              ClientLocationPreview(
                latitude: client.latitude,
                longitude: client.longitude,
                resolvedUrl: client.locationUrl,
              ),
            );
          }

          final preview = await resolveClientLocationPreview(
            client.locationUrl,
            dio: dio,
          );
          return MapEntry(client.id, preview);
        }),
      );

      if (!mounted) return;
      setState(() {
        _locationSignature = signature;
        _locationsByClientId = {
          for (final entry in entries)
            if (entry.value.hasCoordinates) entry.key: entry.value,
        };
      });
    } finally {
      if (mounted) {
        setState(() => _resolvingLocations = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientsState = ref.watch(clientesControllerProvider);
    final ordersState = ref.watch(serviceOrdersListControllerProvider);

    final nextSignature = clientsState.items
        .map(
          (client) =>
              '${client.id}|${client.locationUrl ?? ''}|${client.latitude ?? ''}|${client.longitude ?? ''}',
        )
        .join('||');
    if (!_resolvingLocations && nextSignature != _locationSignature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _resolveLocations();
        }
      });
    }

    final items = _buildMapItems(
      clients: clientsState.items,
      orders: ordersState.items,
      locationsByClientId: _locationsByClientId,
    );
    final summary = _MapSummary.fromItems(items);
    final nextTileWarmSignature = _buildTileWarmSignature(items);
    if (items.isNotEmpty && nextTileWarmSignature != _tileWarmSignature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_warmInitialTileCache(items));
        }
      });
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFEAF6FB)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: clientsState.loading && clientsState.items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _FullscreenMapSurface(
                      items: items,
                      summary: summary,
                      isResolvingLocations:
                          _resolvingLocations ||
                          clientsState.refreshing ||
                          ordersState.refreshing,
                      onClientTap: _openClient,
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FloatingMapButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Volver',
                      onPressed: _goBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          _buildTopLabel(summary),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w300,
                                color: Colors.white.withValues(alpha: 0.88),
                                letterSpacing: 0.25,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openClient(String clientId) {
    context.push(Routes.clienteDetail(clientId));
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go(Routes.serviceOrders);
  }

  Future<void> _warmInitialTileCache(List<_ClientMapItem> items) async {
    _tileWarmSignature = _buildTileWarmSignature(items);
    await FulltechMapTileCacheManager.warmTileUrls(
      _buildInitialTileUrls(items),
    );
  }
}

String _buildTopLabel(_MapSummary summary) {
  if (summary.total == 0) return 'Sin ubicaciones disponibles';
  if (summary.inProgress > 0) {
    return '${summary.total} ubicaciones · ${summary.inProgress} en proceso';
  }
  return '${summary.total} ubicaciones activas';
}

List<_ClientMapItem> _buildMapItems({
  required List<ClienteModel> clients,
  required List<ServiceOrderModel> orders,
  required Map<String, ClientLocationPreview> locationsByClientId,
}) {
  final ordersByClientId = <String, List<ServiceOrderModel>>{};
  for (final order in orders) {
    ordersByClientId
        .putIfAbsent(order.clientId, () => <ServiceOrderModel>[])
        .add(order);
  }

  final items = <_ClientMapItem>[];
  for (final client in clients) {
    final preview = locationsByClientId[client.id];
    if (preview == null || !preview.hasCoordinates) continue;
    final clientOrders =
        ordersByClientId[client.id] ?? const <ServiceOrderModel>[];
    items.add(
      _ClientMapItem(
        client: client,
        location: LatLng(preview.latitude!, preview.longitude!),
        state: _ClientServiceState.fromOrders(clientOrders),
      ),
    );
  }

  items.sort((left, right) {
    final byPriority = left.state.priority.compareTo(right.state.priority);
    if (byPriority != 0) return byPriority;
    return left.client.nombre.toLowerCase().compareTo(
      right.client.nombre.toLowerCase(),
    );
  });

  return items;
}

class _FullscreenMapSurface extends StatelessWidget {
  const _FullscreenMapSurface({
    required this.items,
    required this.summary,
    required this.isResolvingLocations,
    required this.onClientTap,
  });

  final List<_ClientMapItem> items;
  final _MapSummary summary;
  final bool isResolvingLocations;
  final ValueChanged<String> onClientTap;

  @override
  Widget build(BuildContext context) {
    final center = _mapCenter(items);
    final zoom = items.length <= 1
        ? 15.5
        : items.length <= 4
        ? 11.5
        : 9.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: SizedBox.expand(
            child: FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: zoom),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.fulltech.app',
                  tileProvider: _CachedMapTileProvider(),
                  panBuffer: 2,
                ),
                MarkerLayer(
                  markers: [
                    for (final item in items)
                      Marker(
                        point: item.location,
                        width: 84,
                        height: 84,
                        child: _MapMarker(item: item, onTap: onClientTap),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (summary.total == 0)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'No hay puntos para mostrar',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (isResolvingLocations)
          const Positioned(
            right: 16,
            top: 56,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
      ],
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.item, required this.onTap});

  final _ClientMapItem item;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => onTap(item.client.id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: item.state.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: item.state.color.withValues(alpha: 0.34),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.client.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatingMapButton extends StatelessWidget {
  const _FloatingMapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Ink(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

class _CachedMapTileProvider extends TileProvider {
  _CachedMapTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _CachedMapTileImageProvider(
      url,
      headers: headers.isEmpty ? null : headers,
    );
  }
}

@immutable
class _CachedMapTileImageProvider
    extends ImageProvider<_CachedMapTileImageProvider> {
  const _CachedMapTileImageProvider(this.url, {this.headers});

  final String url;
  final Map<String, String>? headers;

  @override
  Future<_CachedMapTileImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_CachedMapTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedMapTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Tile URL', url),
      ],
    );
  }

  Future<Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      final bytes = await _readAndValidateBytes();
      return decode(await ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      await FulltechMapTileCacheManager.removeFile(url);
      try {
        final bytes = await _readAndValidateBytes();
        return decode(await ImmutableBuffer.fromUint8List(bytes));
      } catch (_) {
        return decode(
          await ImmutableBuffer.fromUint8List(_transparentTileBytes),
        );
      }
    }
  }

  Future<Uint8List> _readAndValidateBytes() async {
    final bytes = await FulltechMapTileCacheManager.getTileBytes(
      url,
      headers: headers ?? const <String, String>{},
    );
    if (!_looksLikeImage(bytes)) {
      throw const FormatException('Tile payload is not a supported image');
    }
    return bytes;
  }

  bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 12) return false;

    final isPng =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    if (isPng) return true;

    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (isJpeg) return true;

    final isGif =
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    if (isGif) return true;

    final isWebP =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isWebP;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _CachedMapTileImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}

final Uint8List _transparentTileBytes = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _ClientMapItem {
  const _ClientMapItem({
    required this.client,
    required this.location,
    required this.state,
  });

  final ClienteModel client;
  final LatLng location;
  final _ClientServiceState state;
}

class _MapSummary {
  const _MapSummary({required this.total, required this.inProgress});

  final int total;
  final int inProgress;

  factory _MapSummary.fromItems(List<_ClientMapItem> items) {
    var inProgress = 0;
    for (final item in items) {
      if (item.state.kind == _ClientServiceKind.inProgress) {
        inProgress++;
      }
    }
    return _MapSummary(total: items.length, inProgress: inProgress);
  }
}

enum _ClientServiceKind { serviced, inProgress, noService }

class _ClientServiceState {
  const _ClientServiceState({required this.kind});

  final _ClientServiceKind kind;

  factory _ClientServiceState.fromOrders(List<ServiceOrderModel> orders) {
    if (orders.isEmpty) {
      return const _ClientServiceState(kind: _ClientServiceKind.noService);
    }

    final hasActive = orders.any(
      (order) =>
          order.status == ServiceOrderStatus.enProceso ||
          order.status == ServiceOrderStatus.pendiente,
    );
    if (hasActive) {
      return const _ClientServiceState(kind: _ClientServiceKind.inProgress);
    }

    final hasCompleted = orders.any(
      (order) => order.status == ServiceOrderStatus.finalizado,
    );
    if (hasCompleted) {
      return const _ClientServiceState(kind: _ClientServiceKind.serviced);
    }

    return const _ClientServiceState(kind: _ClientServiceKind.noService);
  }

  Color get color {
    switch (kind) {
      case _ClientServiceKind.serviced:
        return const Color(0xFF15803D);
      case _ClientServiceKind.inProgress:
        return const Color(0xFFF59E0B);
      case _ClientServiceKind.noService:
        return const Color(0xFFDC2626);
    }
  }

  int get priority {
    switch (kind) {
      case _ClientServiceKind.inProgress:
        return 0;
      case _ClientServiceKind.noService:
        return 1;
      case _ClientServiceKind.serviced:
        return 2;
    }
  }
}

LatLng _mapCenter(List<_ClientMapItem> items) {
  if (items.isEmpty) return const LatLng(18.4861, -69.9312);

  final latitude =
      items.fold<double>(0, (sum, item) => sum + item.location.latitude) /
      items.length;
  final longitude =
      items.fold<double>(0, (sum, item) => sum + item.location.longitude) /
      items.length;
  return LatLng(latitude, longitude);
}

String _buildTileWarmSignature(List<_ClientMapItem> items) {
  return items
      .map(
        (item) =>
            '${item.client.id}:${item.location.latitude.toStringAsFixed(4)},${item.location.longitude.toStringAsFixed(4)}',
      )
      .join('|');
}

Iterable<String> _buildInitialTileUrls(List<_ClientMapItem> items) sync* {
  if (items.isEmpty) return;

  final center = _mapCenter(items);
  final zoom = items.length <= 1
      ? 15
      : items.length <= 4
      ? 11
      : 9;
  final tilePoint = _latLngToTile(center, zoom);

  for (var dx = -2; dx <= 2; dx++) {
    for (var dy = -2; dy <= 2; dy++) {
      yield 'https://tile.openstreetmap.org/$zoom/${tilePoint.x + dx}/${tilePoint.y + dy}.png';
    }
  }
}

_TilePoint _latLngToTile(LatLng latLng, int zoom) {
  final scale = 1 << zoom;
  final x = ((latLng.longitude + 180.0) / 360.0 * scale).floor();
  final latitudeRadians = latLng.latitude * math.pi / 180.0;
  final y =
      ((1.0 -
                  (math.log(
                        math.tan(latitudeRadians) +
                            1.0 / math.cos(latitudeRadians),
                      ) /
                      math.pi)) /
              2.0 *
              scale)
          .floor();
  return _TilePoint(x: x, y: y);
}

class _TilePoint {
  const _TilePoint({required this.x, required this.y});

  final int x;
  final int y;
}
