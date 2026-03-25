import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
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
        _timeline = timeline?.items.toList(growable: false) ?? const [];
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
      return;
    }
    if (event.eventType == 'service') {
      context.go(Routes.serviceOrders);
    }
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  String _timelineTypeLabel(String type) {
    switch (type) {
      case 'sale':
        return 'Venta';
      case 'cotizacion':
        return 'Cotizacion';
      case 'service':
        return 'Servicio';
      default:
        return 'Actividad';
    }
  }

  IconData _timelineIcon(String type) {
    switch (type) {
      case 'sale':
        return Icons.point_of_sale_rounded;
      case 'cotizacion':
        return Icons.description_outlined;
      case 'service':
        return Icons.build_circle_outlined;
      default:
        return Icons.history_rounded;
    }
  }

  String _timelineSummary(ClienteTimelineEvent event) {
    final parts = <String>[];
    final category = (event.meta['category'] ?? '').toString().trim();
    final orderNumber = (event.meta['orderNumber'] ?? '').toString().trim();
    final phase = (event.meta['currentPhase'] ?? '').toString().trim();
    final userName = (event.userName ?? '').trim();

    if (orderNumber.isNotEmpty) parts.add('Orden $orderNumber');
    if (category.isNotEmpty) parts.add(category);
    if (phase.isNotEmpty) parts.add(phase);
    if (userName.isNotEmpty) parts.add('Por $userName');

    return parts.join(' • ');
  }

  List<_ClientFactData> _buildClientFacts(ClienteProfileResponse? profile) {
    final client = profile?.client;
    final createdBy = profile?.createdBy;

    return [
      _ClientFactData(
        label: 'Telefono',
        value: (client?.telefono ?? _cliente?.telefono ?? '').trim(),
        icon: Icons.call_outlined,
      ),
      _ClientFactData(
        label: 'Correo',
        value: (client?.email ?? _cliente?.correo ?? '').trim(),
        icon: Icons.alternate_email_rounded,
      ),
      _ClientFactData(
        label: 'Direccion',
        value: (client?.direccion ?? _cliente?.direccion ?? '').trim(),
        icon: Icons.location_on_outlined,
      ),
      _ClientFactData(
        label: 'Creado por',
        value: createdBy?.displayName ?? '',
        icon: Icons.person_outline_rounded,
      ),
      _ClientFactData(
        label: 'Creado',
        value: client?.createdAt != null ? _formatDate(client!.createdAt) : '',
        icon: Icons.calendar_today_outlined,
      ),
      _ClientFactData(
        label: 'Ultima actividad',
        value: _formatDate(profile?.metrics.lastActivityAt ?? client?.lastActivityAt),
        icon: Icons.schedule_rounded,
      ),
    ].where((item) => item.value.trim().isNotEmpty && item.value.trim() != '-').toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final profile = _profile;
    final theme = Theme.of(context);
    final fallbackLocation = parseClientLocationPreview(_cliente?.locationUrl);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: CustomAppBar(
        title: _cliente?.nombre ?? 'Detalle del cliente',
        fallbackRoute: Routes.clientes,
        showLogo: false,
        showDepartmentLabel: false,
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
                  _ClientHeroCard(
                    name: profile?.client.nombre ?? _cliente?.nombre ?? 'Cliente',
                    phone: profile?.client.telefono ?? _cliente?.telefono,
                    email: profile?.client.email ?? _cliente?.correo,
                    totalPurchased: _formatMoney(profile?.metrics.salesTotal),
                    lastActivity: _formatDate(
                      profile?.metrics.lastActivityAt ??
                          profile?.client.lastActivityAt,
                    ),
                    deleted: profile?.client.isDeleted ?? _cliente?.isDeleted ?? false,
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Resumen comercial',
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(
                          label: 'Ventas',
                          value: '${profile?.metrics.salesCount ?? 0}',
                          helper: _formatMoney(profile?.metrics.salesTotal),
                        ),
                        _MetricCard(
                          label: 'Servicios',
                          value: '${profile?.metrics.servicesCount ?? 0}',
                          helper: _formatDate(profile?.metrics.lastServiceAt),
                        ),
                        _MetricCard(
                          label: 'Cotizaciones',
                          value: '${profile?.metrics.cotizacionesCount ?? 0}',
                          helper: _formatMoney(profile?.metrics.cotizacionesTotal),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Datos del cliente',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ClientFactsGrid(items: _buildClientFacts(profile)),
                        _LocationDetailCard(
                          locationUrl: profile?.client.locationUrl ?? _cliente?.locationUrl,
                          latitude: profile?.client.latitude ?? fallbackLocation.latitude,
                          longitude: profile?.client.longitude ?? fallbackLocation.longitude,
                        ),
                        if (_hasText(profile?.client.notas))
                          _InlineNoteCard(note: profile!.client.notas!.trim()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Actividad del cliente',
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
                        child: _TimelineEventCard(
                          icon: _timelineIcon(event.eventType),
                          badge: _timelineTypeLabel(event.eventType),
                          title: event.title,
                          summary: _timelineSummary(event),
                          date: _formatDate(event.at),
                          amount: event.amount == null ? null : _formatMoney(event.amount),
                          status: (event.status ?? '').trim().isEmpty ? null : event.status!.trim(),
                          onTap: () => _openEvent(event),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(helper, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _ClientHeroCard extends StatelessWidget {
  const _ClientHeroCard({
    required this.name,
    required this.phone,
    required this.email,
    required this.totalPurchased,
    required this.lastActivity,
    required this.deleted,
  });

  final String name;
  final String? phone;
  final String? email;
  final String totalPurchased;
  final String lastActivity;
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(
                    name.isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [if ((phone ?? '').trim().isNotEmpty) phone!.trim(), if ((email ?? '').trim().isNotEmpty) email!.trim()].join(' • ').isEmpty
                            ? 'Expediente del cliente'
                            : [if ((phone ?? '').trim().isNotEmpty) phone!.trim(), if ((email ?? '').trim().isNotEmpty) email!.trim()].join(' • '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (deleted)
                  const Chip(label: Text('Eliminado')),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoBadge(label: 'Total comprado', value: totalPurchased),
                _InfoBadge(label: 'Ultima actividad', value: lastActivity),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientFactData {
  const _ClientFactData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _ClientFactsGrid extends StatelessWidget {
  const _ClientFactsGrid({required this.items});

  final List<_ClientFactData> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;
        final itemWidth = isCompact ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _ClientFactTile(item: item),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _ClientFactTile extends StatelessWidget {
  const _ClientFactTile({required this.item});

  final _ClientFactData item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineNoteCard extends StatelessWidget {
  const _InlineNoteCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notas',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(note),
          ],
        ),
      ),
    );
  }
}

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({
    required this.icon,
    required this.badge,
    required this.title,
    required this.summary,
    required this.date,
    required this.amount,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String badge;
  final String title;
  final String summary;
  final String date;
  final String? amount;
  final String? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(summary, style: theme.textTheme.bodyMedium),
                    ],
                    if (status != null && status!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Estado: ${status!.trim()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (amount != null) ...[
                const SizedBox(width: 12),
                Text(
                  amount!,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
