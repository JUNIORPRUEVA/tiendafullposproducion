import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import 'application/clientes_controller.dart';
import 'client_location_utils.dart';
import 'cliente_model.dart';
import 'cliente_profile_model.dart';
import 'cliente_timeline_model.dart';
import 'data/clientes_repository.dart';

class ClienteDetailScreen extends ConsumerStatefulWidget {
  const ClienteDetailScreen({super.key, required this.clienteId});

  final String clienteId;

  @override
  ConsumerState<ClienteDetailScreen> createState() =>
      _ClienteDetailScreenState();
}

class _ClienteDetailScreenState extends ConsumerState<ClienteDetailScreen> {
  bool _loading = true;
  bool _deleting = false;
  String? _error;
  ClienteModel? _cliente;
  ClienteProfileResponse? _profile;
  List<ClienteTimelineEvent> _timeline = const [];

  static const Duration _detailTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    ClienteModel? cachedClient;
    try {
      cachedClient = await ref
          .read(clientesControllerProvider.notifier)
          .getById(widget.clienteId);
    } catch (_) {
      cachedClient = null;
    }

    if (!mounted) return;
    if (cachedClient != null) {
      setState(() => _cliente = cachedClient);
    }

    if (widget.clienteId.startsWith('local_')) {
      setState(() {
        _profile = null;
        _timeline = const [];
        _loading = false;
      });
      return;
    }

    try {
      final repo = ref.read(clientesRepositoryProvider);
      final results = await Future.wait([
        repo.getClientProfile(id: widget.clienteId).timeout(_detailTimeout),
        repo
            .getClientTimeline(id: widget.clienteId, take: 120)
            .timeout(_detailTimeout)
            .then<ClienteTimelineResponse?>((value) => value)
            .catchError((_) => null),
      ]);

      final profile = results[0] as ClienteProfileResponse;
      final timeline = results[1] as ClienteTimelineResponse?;

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _timeline =
            timeline?.items
                .where(
                  (item) =>
                      item.eventType == 'sale' ||
                      item.eventType == 'cotizacion',
                )
                .toList(growable: false) ??
            const [];
        _cliente = ClienteModel.fromJson({
          'id': profile.client.id,
          'nombre': profile.client.nombre,
          'telefono': profile.client.telefono,
          'direccion': profile.client.direccion,
          'location_url': profile.client.locationUrl,
          'email': profile.client.email,
          'isDeleted': profile.client.isDeleted,
          'createdAt': profile.client.createdAt?.toIso8601String(),
          'updatedAt': profile.client.updatedAt?.toIso8601String(),
        });
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _cliente == null ? 'No se pudo cargar el cliente' : null;
        _profile = null;
        _timeline = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteClient() async {
    final client = _cliente;
    if (client == null || _deleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar cliente'),
          content: Text(
            'Se eliminara el cliente ${client.nombre}. Esta accion no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(clientesControllerProvider.notifier).remove(client.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
      context.go(Routes.clientes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _formatMoney(num? value) {
    return NumberFormat.currency(
      symbol: 'RD\$ ',
      decimalDigits: 2,
    ).format(value ?? 0);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('yyyy-MM-dd h:mm a', 'es_DO').format(value.toLocal());
  }

  void _openEvent(ClienteTimelineEvent event) {
    final phone = (_cliente?.telefono ?? '').trim();
    if (event.eventType == 'cotizacion' && phone.isNotEmpty) {
      context.go(
        '${Routes.cotizacionesHistorial}?customerPhone=${Uri.encodeQueryComponent(phone)}',
      );
      return;
    }
    if (event.eventType == 'sale') {
      context.go(Routes.ventas);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final profile = _profile;
    final theme = Theme.of(context);
    final fallbackLocation = parseClientLocationPreview(_cliente?.locationUrl);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: AppBar(
        leading: AppNavigator.maybeBackButton(
          context,
          fallbackRoute: Routes.clientes,
        ),
        title: Text(_cliente?.nombre ?? 'Detalle del cliente'),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: _cliente == null || _deleting
                ? null
                : () => context.push(Routes.clienteEdit(_cliente!.id)),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _cliente == null || _deleting ? null : _deleteClient,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.client.nombre ??
                                _cliente?.nombre ??
                                'Cliente',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _DetailLine(
                            'Telefono',
                            profile?.client.telefono ??
                                _cliente?.telefono ??
                                '-',
                          ),
                          _DetailLine(
                            'Correo',
                            (profile?.client.email ?? _cliente?.correo ?? '')
                                    .trim()
                                    .isEmpty
                                ? '-'
                                : (profile?.client.email ??
                                          _cliente?.correo ??
                                          '')
                                      .trim(),
                          ),
                          _DetailLine(
                            'Direccion',
                            (profile?.client.direccion ??
                                        _cliente?.direccion ??
                                        '')
                                    .trim()
                                    .isEmpty
                                ? '-'
                                : (profile?.client.direccion ??
                                          _cliente?.direccion ??
                                          '')
                                      .trim(),
                          ),
                          _LocationDetailCard(
                            locationUrl:
                                profile?.client.locationUrl ??
                                _cliente?.locationUrl,
                            latitude:
                                profile?.client.latitude ??
                                fallbackLocation.latitude,
                            longitude:
                                profile?.client.longitude ??
                                fallbackLocation.longitude,
                          ),
                          _DetailLine(
                            'Creado por',
                            profile?.createdBy?.label ?? '-',
                          ),
                          _DetailLine(
                            'Ultima actividad',
                            _formatDate(
                              profile?.metrics.lastActivityAt ??
                                  profile?.client.lastActivityAt,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Ventas',
                          value: '${profile?.metrics.salesCount ?? 0}',
                          helper: _formatMoney(profile?.metrics.salesTotal),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Cotizaciones',
                          value: '${profile?.metrics.cotizacionesCount ?? 0}',
                          helper: _formatMoney(
                            profile?.metrics.cotizacionesTotal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Historial',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_timeline.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No hay eventos disponibles para este cliente.',
                        ),
                      ),
                    )
                  else
                    ..._timeline.map(
                      (event) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: ListTile(
                            leading: Icon(
                              event.eventType == 'sale'
                                  ? Icons.point_of_sale_rounded
                                  : Icons.description_outlined,
                            ),
                            title: Text(event.title),
                            subtitle: Text(_formatDate(event.at)),
                            trailing: event.amount == null
                                ? null
                                : Text(_formatMoney(event.amount)),
                            onTap: () => _openEvent(event),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _LocationDetailCard extends ConsumerWidget {
  const _LocationDetailCard({
    required this.locationUrl,
    this.latitude,
    this.longitude,
  });

  final String? locationUrl;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final normalizedUrl = normalizeClientLocationUrl(locationUrl);
    final uri = normalizedUrl.isEmpty ? null : Uri.tryParse(normalizedUrl);
    final directPreview = ClientLocationPreview(
      latitude: latitude,
      longitude: longitude,
      resolvedUrl: normalizedUrl.isEmpty ? null : normalizedUrl,
    );

    if (normalizedUrl.isEmpty && !directPreview.hasCoordinates) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ubicacion',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FutureBuilder<ClientLocationPreview>(
                    future: resolveClientLocationPreview(
                      normalizedUrl,
                      dio: ref.read(dioProvider),
                    ),
                    initialData: directPreview,
                    builder: (context, snapshot) {
                      final preview = snapshot.data ?? directPreview;

                      if (preview.hasCoordinates) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 220,
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
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${preview.latitude!.toStringAsFixed(6)}, ${preview.longitude!.toStringAsFixed(6)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(),
                        );
                      }

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'No se pudieron resolver coordenadas del enlace, pero la ubicacion sigue vinculada al cliente.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      );
                    },
                  ),
                  if (uri != null) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => safeOpenUrl(context, uri),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Abrir en mapa'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(helper, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
