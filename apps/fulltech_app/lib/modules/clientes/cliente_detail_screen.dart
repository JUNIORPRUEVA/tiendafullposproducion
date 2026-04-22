import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/realtime/operations_realtime_service.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/clientes_controller.dart';
import 'client_location_utils.dart';
import 'cliente_model.dart';
import 'cliente_profile_model.dart';
import 'cliente_timeline_model.dart';
import 'data/cliente_detail_local_repository.dart';
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
  bool _refreshing = false;
  bool _deleting = false;
  String? _error;
  ClienteModel? _cliente;
  ClienteProfileResponse? _profile;
  List<ClienteTimelineEvent> _timeline = const [];
  List<_TimelineGroupData> _timelineGroups = const [];
  Future<ClientLocationPreview>? _locationPreviewFuture;
  String _locationPreviewCacheKey = '';
  StreamSubscription<ClientsRealtimeMessage>? _clientsRealtimeSubscription;

  static const Duration _detailTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _clientsRealtimeSubscription = ref
        .read(operationsRealtimeServiceProvider)
        .clientStream
        .listen(_handleRealtimeMessage);
    _load();
  }

  @override
  void dispose() {
    _clientsRealtimeSubscription?.cancel();
    super.dispose();
  }

  void _handleRealtimeMessage(ClientsRealtimeMessage message) {
    if (!mounted) return;
    final incomingId = (message.clientId ?? '').trim();
    final currentId = widget.clienteId.trim();

    if (message.type == 'client.bulkDeleted') {
      context.go(Routes.clientes);
      return;
    }

    if (incomingId.isEmpty || incomingId != currentId) {
      return;
    }

    if (message.type == 'client.deleted') {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Este cliente fue eliminado.')),
      );
      context.go(Routes.clientes);
      return;
    }

    unawaited(_load());
  }

  Future<void> _load() async {
    final hadRenderableData =
        _cliente != null || _profile != null || _timeline.isNotEmpty;
    if (mounted) {
      setState(() {
        _loading = !hadRenderableData;
        _refreshing = hadRenderableData;
        _error = null;
      });
    }

    final detailLocalRepository = ref.read(
      clienteDetailLocalRepositoryProvider,
    );

    ClienteModel? cachedClient;
    ClienteDetailLocalSnapshot localSnapshot =
        const ClienteDetailLocalSnapshot();

    try {
      final results = await Future.wait<dynamic>([
        ref.read(clientesControllerProvider.notifier).getById(widget.clienteId),
        detailLocalRepository.read(widget.clienteId),
      ]);
      cachedClient = results[0] as ClienteModel?;
      localSnapshot = results[1] as ClienteDetailLocalSnapshot;
    } catch (_) {
      try {
        cachedClient = await ref
            .read(clientesControllerProvider.notifier)
            .getById(widget.clienteId);
      } catch (_) {
        cachedClient = null;
      }
      try {
        localSnapshot = await detailLocalRepository.read(widget.clienteId);
      } catch (_) {
        localSnapshot = const ClienteDetailLocalSnapshot();
      }
    }

    if (!mounted) return;
    final effectiveLocalClient =
        localSnapshot.profile == null
            ? cachedClient
            : _profileToClient(localSnapshot.profile!, fallback: cachedClient);

    if (effectiveLocalClient != null || localSnapshot.hasData) {
      setState(() {
        _cliente = effectiveLocalClient ?? _cliente;
        _profile = localSnapshot.profile ?? _profile;
        _timeline = localSnapshot.timeline.isNotEmpty
            ? localSnapshot.timeline
            : _timeline;
        _timelineGroups = _computeTimelineGroups(_timeline);
        _syncLocationPreview();
        _loading = false;
        _refreshing = !widget.clienteId.startsWith('local_');
      });
    }

    if (widget.clienteId.startsWith('local_')) {
      setState(() {
        _profile = null;
        _timeline = const [];
        _timelineGroups = const [];
        _loading = false;
        _refreshing = false;
      });
      return;
    }

    try {
      final repo = ref.read(clientesRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repo.getClientProfile(id: widget.clienteId).timeout(_detailTimeout),
        repo
            .getClientTimeline(id: widget.clienteId, take: 120)
            .timeout(_detailTimeout)
            .then<ClienteTimelineResponse?>((value) => value)
            .catchError((_) => null),
      ]);

      final profile = results[0] as ClienteProfileResponse;
      final timeline = results[1] as ClienteTimelineResponse?;
      final mergedClient = _profileToClient(profile, fallback: cachedClient);

      await detailLocalRepository.write(
        clientId: widget.clienteId,
        profile: profile,
        timeline: timeline?.items.toList(growable: false) ?? const [],
      );

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _timeline = timeline?.items.toList(growable: false) ?? const [];
        _timelineGroups = _computeTimelineGroups(_timeline);
        _cliente = mergedClient;
        _syncLocationPreview();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final hasFallbackData =
            _cliente != null || _profile != null || _timeline.isNotEmpty;
        _error = hasFallbackData ? null : 'No se pudo cargar el cliente';
        if (!hasFallbackData) {
          _profile = null;
          _timeline = const [];
          _timelineGroups = const [];
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  ClienteModel _profileToClient(
    ClienteProfileResponse profile, {
    ClienteModel? fallback,
  }) {
    return ClienteModel.fromJson({
      'id': profile.client.id,
      'ownerId': profile.client.ownerId ?? fallback?.ownerId ?? '',
      'nombre': profile.client.nombre,
      'telefono': profile.client.telefono,
      'direccion': profile.client.direccion,
      'location_url': profile.client.locationUrl,
      'latitude': profile.client.latitude ?? fallback?.latitude,
      'longitude': profile.client.longitude ?? fallback?.longitude,
      'email': profile.client.email,
      'isDeleted': profile.client.isDeleted,
      'createdAt': profile.client.createdAt?.toIso8601String(),
      'updatedAt': profile.client.updatedAt?.toIso8601String(),
    });
  }

  List<_TimelineGroupData> _computeTimelineGroups(
    List<ClienteTimelineEvent> timeline,
  ) {
    if (timeline.isEmpty) {
      return const [];
    }

    final grouped = <String, List<ClienteTimelineEvent>>{};
    for (final event in timeline) {
      grouped
          .putIfAbsent(event.eventType, () => <ClienteTimelineEvent>[])
          .add(event);
    }

    const order = ['service', 'cotizacion', 'sale'];
    final items = <_TimelineGroupData>[];
    for (final type in order) {
      final rows = grouped.remove(type);
      if (rows == null || rows.isEmpty) continue;
      items.add(
        _TimelineGroupData(
          type: type,
          label: _timelineTypeLabel(type),
          items: rows,
        ),
      );
    }

    for (final entry in grouped.entries) {
      if (entry.value.isEmpty) continue;
      items.add(
        _TimelineGroupData(
          type: entry.key,
          label: _timelineTypeLabel(entry.key),
          items: entry.value,
        ),
      );
    }
    return items;
  }

  void _syncLocationPreview() {
    final normalizedUrl = normalizeClientLocationUrl(
      _profile?.client.locationUrl ?? _cliente?.locationUrl,
    );
    final latitude = _profile?.client.latitude ?? _cliente?.latitude;
    final longitude = _profile?.client.longitude ?? _cliente?.longitude;
    final nextKey = '$normalizedUrl|$latitude|$longitude';
    if (_locationPreviewCacheKey == nextKey) {
      return;
    }

    _locationPreviewCacheKey = nextKey;
    final directPreview = ClientLocationPreview(
      latitude: latitude,
      longitude: longitude,
      resolvedUrl: normalizedUrl.isEmpty ? null : normalizedUrl,
    );
    _locationPreviewFuture = Future.value(directPreview);

    if (normalizedUrl.isEmpty) {
      return;
    }

    _locationPreviewFuture = resolveClientLocationPreview(
      normalizedUrl,
      dio: ref.read(dioProvider),
    );
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
    final clienteId = widget.clienteId.trim();
    final clienteNombre = (_cliente?.nombre ?? _profile?.client.nombre ?? '')
        .trim();
    final source = (event.meta['source'] ?? '').toString().trim();
    if (event.eventType == 'cotizacion' && event.eventId.trim().isNotEmpty) {
      context.go(
        '${Routes.cotizaciones}?quotationId=${Uri.encodeQueryComponent(event.eventId)}',
      );
      return;
    }
    if (event.eventType == 'sale') {
      if (clienteId.isNotEmpty && !clienteId.startsWith('local_')) {
        final query = StringBuffer(
          '${Routes.ventas}?customerId=${Uri.encodeQueryComponent(clienteId)}',
        );
        if (clienteNombre.isNotEmpty) {
          query.write(
            '&customerName=${Uri.encodeQueryComponent(clienteNombre)}',
          );
        }
        context.go(query.toString());
        return;
      }
      context.go(Routes.ventas);
      return;
    }
    if (event.eventType == 'service' && event.eventId.trim().isNotEmpty) {
      if (source == 'legacy_service') {
        return;
      }
      final serviceOrderId = (event.meta['serviceOrderId'] ?? event.eventId)
          .toString()
          .trim();
      if (serviceOrderId.isNotEmpty) {
        context.go(Routes.serviceOrderById(serviceOrderId));
      }
    }
  }

  bool _canOpenEvent(ClienteTimelineEvent event) {
    if (event.eventType == 'sale') return true;
    if (event.eventType == 'cotizacion') return event.eventId.trim().isNotEmpty;
    if (event.eventType != 'service') return false;

    final source = (event.meta['source'] ?? '').toString().trim();
    if (source == 'legacy_service') return false;

    final serviceOrderId = (event.meta['serviceOrderId'] ?? event.eventId)
        .toString()
        .trim();
    return serviceOrderId.isNotEmpty;
  }

  bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

  String _timelineTypeLabel(String type) {
    switch (type) {
      case 'sale':
        return 'Ventas';
      case 'cotizacion':
        return 'Cotizaciones';
      case 'service':
        return 'Servicios y referencias';
      default:
        return 'Otros procesos';
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
    final source = (event.meta['source'] ?? '').toString().trim();
    final category = (event.meta['category'] ?? '').toString().trim();
    final orderNumber = (event.meta['orderNumber'] ?? '').toString().trim();
    final phase = (event.meta['currentPhase'] ?? '').toString().trim();
    final serviceType = (event.meta['serviceType'] ?? '').toString().trim();
    final note = (event.meta['note'] ?? '').toString().trim();
    final userName = (event.userName ?? '').trim();
    final assignedToName = (event.meta['assignedToName'] ?? '')
        .toString()
        .trim();
    final technicianName = (event.meta['technicianName'] ?? '')
        .toString()
        .trim();
    final contentPreview = (event.meta['contentPreview'] ?? '')
        .toString()
        .trim();
    final technicalNote = (event.meta['technicalNote'] ?? '').toString().trim();
    final extraRequirements = (event.meta['extraRequirements'] ?? '')
        .toString()
        .trim();
    final titleSnapshot = (event.meta['titleSnapshot'] ?? '').toString().trim();
    final evidenceType = _humanizeCode(
      (event.meta['evidenceType'] ?? '').toString(),
    );
    final reportType = _humanizeCode(
      (event.meta['reportType'] ?? '').toString(),
    );
    final paymentStatus = _humanizeCode(
      (event.meta['paymentStatus'] ?? '').toString(),
    );

    if (source == 'service_order') {
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (assignedToName.isNotEmpty) parts.add('Asignado a $assignedToName');
      if (technicalNote.isNotEmpty) parts.add(technicalNote);
      if (extraRequirements.isNotEmpty) parts.add(extraRequirements);
      if (userName.isNotEmpty) parts.add('Creado por $userName');
      return parts.join(' • ');
    }

    if (source == 'service_evidence') {
      if (evidenceType.isNotEmpty) parts.add(evidenceType);
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (contentPreview.isNotEmpty) parts.add(contentPreview);
      if (assignedToName.isNotEmpty) parts.add('Tecnico $assignedToName');
      if (userName.isNotEmpty) parts.add('Registrado por $userName');
      return parts.join(' • ');
    }

    if (source == 'service_report') {
      if (reportType.isNotEmpty) parts.add(reportType);
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (contentPreview.isNotEmpty) parts.add(contentPreview);
      if (assignedToName.isNotEmpty) parts.add('Tecnico $assignedToName');
      if (userName.isNotEmpty) parts.add('Registrado por $userName');
      return parts.join(' • ');
    }

    if (source == 'legacy_service') {
      if (orderNumber.isNotEmpty) parts.add('Orden $orderNumber');
      if (titleSnapshot.isNotEmpty) parts.add(titleSnapshot);
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (phase.isNotEmpty) parts.add(_humanizeCode(phase));
      if (paymentStatus.isNotEmpty) parts.add('Pago $paymentStatus');
      if (contentPreview.isNotEmpty) parts.add(contentPreview);
      if (technicianName.isNotEmpty) parts.add('Tecnico $technicianName');
      if (userName.isNotEmpty) parts.add('Creado por $userName');
      return parts.join(' • ');
    }

    if (orderNumber.isNotEmpty) parts.add('Orden $orderNumber');
    if (serviceType.isNotEmpty) parts.add(serviceType.replaceAll('_', ' '));
    if (category.isNotEmpty) parts.add(category);
    if (phase.isNotEmpty) parts.add(phase);
    if (note.isNotEmpty) parts.add(note);
    if (userName.isNotEmpty) parts.add('Por $userName');

    return parts.join(' • ');
  }

  String _timelineStatusLabel(ClienteTimelineEvent event) {
    final raw = (event.status ?? '').trim().toLowerCase();
    final source = (event.meta['source'] ?? '').toString().trim();
    if (raw.isEmpty) {
      if (source == 'service_evidence' || source == 'service_report') {
        return 'Registrado';
      }
      return event.eventType == 'sale' ? 'Finalizado' : 'Pendiente';
    }

    switch (raw) {
      case 'finalized':
      case 'finalizado':
      case 'completed':
        return 'Finalizado';
      case 'cancelled':
      case 'cancelado':
        return 'Cancelado';
      case 'in_process':
      case 'en_proceso':
      case 'en proceso':
      case 'in_progress':
      case 'in progress':
        return 'En proceso';
      case 'reserved':
      case 'reserva':
        return 'Reservado';
      case 'pospuesta':
      case 'postponed':
        return 'Pospuesta';
      default:
        return raw == 'pending' || raw == 'pendiente'
            ? 'Pendiente'
            : _humanizeCode(raw);
    }
  }

  Color _timelineStatusColor(BuildContext context, ClienteTimelineEvent event) {
    final label = _timelineStatusLabel(event);
    switch (label) {
      case 'Finalizado':
        return const Color(0xFF2E8B57);
      case 'Cancelado':
        return Theme.of(context).colorScheme.error;
      case 'Registrado':
        return const Color(0xFF2B6CB0);
      case 'En proceso':
        return const Color(0xFFD98324);
      case 'Reservado':
        return const Color(0xFF8C6A03);
      case 'Pospuesta':
        return const Color(0xFFA05A2C);
      case 'Pendiente':
      default:
        return const Color(0xFFD98324);
    }
  }

  String _humanizeCode(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';

    return normalized
        .replaceAll('-', '_')
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  List<_ClientMetricData> _buildMetricItems(ClienteProfileResponse? profile) {
    final metrics = profile?.metrics;

    return [
      _ClientMetricData(
        label: 'Ventas',
        value: '${metrics?.salesCount ?? 0}',
        helper: _formatMoney(metrics?.salesTotal),
      ),
      _ClientMetricData(
        label: 'Servicios',
        value: '${metrics?.servicesCount ?? 0}',
        helper:
            'OT ${metrics?.serviceOrdersCount ?? 0} • Legacy ${metrics?.legacyServicesCount ?? 0}',
      ),
      _ClientMetricData(
        label: 'Referencias',
        value: '${metrics?.serviceReferencesCount ?? 0}',
        helper: _formatDate(metrics?.lastReferenceAt),
      ),
      _ClientMetricData(
        label: 'Cotizaciones',
        value: '${metrics?.cotizacionesCount ?? 0}',
        helper: _formatMoney(metrics?.cotizacionesTotal),
      ),
    ];
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
            value: createdBy?.label ?? '',
            icon: Icons.person_outline_rounded,
          ),
          _ClientFactData(
            label: 'Creado',
            value: client?.createdAt != null
                ? _formatDate(client!.createdAt)
                : '',
            icon: Icons.calendar_today_outlined,
          ),
          _ClientFactData(
            label: 'Ultima actividad',
            value: _formatDate(
              profile?.metrics.lastActivityAt ?? client?.lastActivityAt,
            ),
            icon: Icons.schedule_rounded,
          ),
          _ClientFactData(
            label: 'Referencias de servicio',
            value: '${profile?.metrics.serviceReferencesCount ?? 0}',
            icon: Icons.link_rounded,
          ),
          _ClientFactData(
            label: 'Cobertura de servicios',
            value:
                'OT ${profile?.metrics.serviceOrdersCount ?? 0} • Legacy ${profile?.metrics.legacyServicesCount ?? 0}',
            icon: Icons.build_circle_outlined,
          ),
        ]
        .where(
          (item) => item.value.trim().isNotEmpty && item.value.trim() != '-',
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final profile = _profile;
    final theme = Theme.of(context);
    final fallbackLocation = parseClientLocationPreview(_cliente?.locationUrl);
    final locationPreviewFuture =
      _locationPreviewFuture ?? Future.value(fallbackLocation);

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
            onPressed: _loading || _refreshing ? null : _load,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
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
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  _ClientHeroCard(
                    name:
                        profile?.client.nombre ?? _cliente?.nombre ?? 'Cliente',
                    phone: profile?.client.telefono ?? _cliente?.telefono,
                    email: profile?.client.email ?? _cliente?.correo,
                    totalPurchased: _formatMoney(profile?.metrics.salesTotal),
                    lastActivity: _formatDate(
                      profile?.metrics.lastActivityAt ??
                          profile?.client.lastActivityAt,
                    ),
                    deleted:
                        profile?.client.isDeleted ??
                        _cliente?.isDeleted ??
                        false,
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Resumen del cliente',
                    child: _MetricGrid(items: _buildMetricItems(profile)),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: 'Datos del cliente',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ClientFactsGrid(items: _buildClientFacts(profile)),
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
                            previewFuture: locationPreviewFuture,
                        ),
                        if (_hasText(profile?.client.notas))
                          _InlineNoteCard(note: profile!.client.notas!.trim()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Historial completo del cliente',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_timeline.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: const Text(
                        'No hay ventas, cotizaciones, servicios ni referencias registradas para este cliente.',
                      ),
                    )
                  else
                    ..._timelineGroups.map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TimelineSection(
                          icon: _timelineIcon(group.type),
                          title: group.label,
                          itemCount: group.items.length,
                          children: group.items
                              .map(
                                (event) => _TimelineEventCard(
                                  icon: _timelineIcon(event.eventType),
                                  title: event.title,
                                  summary: _timelineSummary(event),
                                  date: _formatDate(event.at),
                                  amount: event.amount == null
                                      ? null
                                      : _formatMoney(event.amount),
                                  statusLabel: _timelineStatusLabel(event),
                                  statusColor: _timelineStatusColor(
                                    context,
                                    event,
                                  ),
                                  enabled: _canOpenEvent(event),
                                  onTap: () => _openEvent(event),
                                ),
                              )
                              .toList(growable: false),
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
    required this.previewFuture,
    this.latitude,
    this.longitude,
  });

  final String? locationUrl;
  final Future<ClientLocationPreview> previewFuture;
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: FutureBuilder<ClientLocationPreview>(
              future: previewFuture,
              initialData: directPreview,
              builder: (context, snapshot) {
                final preview = snapshot.data ?? directPreview;

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !preview.hasCoordinates) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.location_on_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preview.hasCoordinates
                                ? 'Ubicacion vinculada correctamente'
                                : 'Ubicacion vinculada sin coordenadas resueltas',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            preview.hasCoordinates
                                ? '${preview.latitude!.toStringAsFixed(6)}, ${preview.longitude!.toStringAsFixed(6)}'
                                : 'Puedes abrir el enlace externo para revisar la ubicacion.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (uri != null) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => safeOpenUrl(context, uri),
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('Abrir en mapa'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                alignment: Alignment.centerLeft,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 3,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              helper,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientMetricData {
  const _ClientMetricData({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_ClientMetricData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 700
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _MetricCard(
                    label: item.label,
                    value: item.value,
                    helper: item.helper,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
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
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
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
    final contactLine = [
      if ((phone ?? '').trim().isNotEmpty) phone!.trim(),
      if ((email ?? '').trim().isNotEmpty) email!.trim(),
    ].join(' • ');

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Text(
                  name.isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    if (contactLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contactLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (deleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Eliminado',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InfoBadge(
                  label: 'Total comprado',
                  value: totalPurchased,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoBadge(
                  label: 'Ultima actividad',
                  value: lastActivity,
                ),
              ),
            ],
          ),
        ],
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
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(10),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
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
        final itemWidth = isCompact
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.30),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, size: 15, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
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
    required this.title,
    required this.summary,
    required this.date,
    required this.amount,
    required this.statusLabel,
    required this.statusColor,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String date;
  final String? amount;
  final String statusLabel;
  final Color statusColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (amount != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            amount!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (enabled)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        else
                          Text(
                            'Solo lectura',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({
    required this.icon,
    required this.title,
    required this.itemCount,
    required this.children,
  });

  final IconData icon;
  final String title;
  final int itemCount;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$itemCount',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _TimelineGroupData {
  const _TimelineGroupData({
    required this.type,
    required this.label,
    required this.items,
  });

  final String type;
  final String label;
  final List<ClienteTimelineEvent> items;
}
