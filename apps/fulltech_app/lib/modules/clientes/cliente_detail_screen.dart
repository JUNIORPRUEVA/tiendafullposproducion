import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../features/operaciones/data/operations_repository.dart';
import '../../features/operaciones/operations_models.dart';
import 'application/clientes_controller.dart';
import 'cliente_model.dart';
import 'cliente_profile_model.dart';
import 'cliente_timeline_model.dart';
import 'data/clientes_repository.dart';
import '../cotizaciones/cotizacion_models.dart';
import '../cotizaciones/data/cotizaciones_repository.dart';
import '../ventas/data/ventas_repository.dart';
import '../ventas/sales_models.dart';

class ClienteDetailScreen extends ConsumerStatefulWidget {
  final String clienteId;

  const ClienteDetailScreen({super.key, required this.clienteId});

  @override
  ConsumerState<ClienteDetailScreen> createState() =>
      _ClienteDetailScreenState();
}

class _ClienteDetailScreenState extends ConsumerState<ClienteDetailScreen> {
  bool _loading = true;
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

    try {
      final repo = ref.read(clientesRepositoryProvider);
      final profileFuture = repo
          .getClientProfile(id: widget.clienteId)
          .timeout(_detailTimeout);
      final timelineFuture = repo
          .getClientTimeline(id: widget.clienteId, take: 120)
          .timeout(_detailTimeout)
          .then<ClienteTimelineResponse?>((v) => v)
          .catchError((_) => null);

      final results = await Future.wait([profileFuture, timelineFuture]);

      final profile = results[0] as ClienteProfileResponse;
      final timeline = results[1] as ClienteTimelineResponse?;

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _timeline = timeline?.items ?? const [];
        _cliente = ClienteModel.fromJson({
          'id': profile.client.id,
          'nombre': profile.client.nombre,
          'telefono': profile.client.telefono,
          'direccion': profile.client.direccion,
          'email': profile.client.email,
          'isDeleted': profile.client.isDeleted,
          'createdAt': profile.client.createdAt?.toIso8601String(),
          'updatedAt': profile.client.updatedAt?.toIso8601String(),
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el cliente';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatMoney(num? value) {
    final safe = value ?? 0;
    final fmt = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);
    return fmt.format(safe);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    return fmt.format(value.toLocal());
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'sale':
        return Icons.point_of_sale;
      case 'cotizacion':
        return Icons.description_outlined;
      case 'service':
        return Icons.build_outlined;
      case 'service_phase':
        return Icons.timeline;
      case 'service_update':
        return Icons.update;
      default:
        return Icons.event_note;
    }
  }

  void _openEvent(ClienteTimelineEvent event) {
    final phone = (_cliente?.telefono ?? '').trim();
    switch (event.eventType) {
      case 'cotizacion':
        if (phone.isEmpty) return;
        context.go(
          '${Routes.cotizacionesHistorial}?customerPhone=${Uri.encodeQueryComponent(phone)}',
        );
        return;
      case 'service':
      case 'service_phase':
      case 'service_update':
        context.go(Routes.operaciones);
        return;
      case 'sale':
        context.go(Routes.ventas);
        return;
      default:
        return;
    }
  }

  Future<void> _openEventDetail(ClienteTimelineEvent event) async {
    final id = event.eventId.trim();
    if (id.isEmpty) return;

    try {
      switch (event.eventType) {
        case 'cotizacion':
          final item = await ref
              .read(cotizacionesRepositoryProvider)
              .getById(id)
              .timeout(_detailTimeout);
          if (!mounted) return;
          _showCotizacionDetailDialog(item);
          return;
        case 'sale':
          final sale = await ref
              .read(ventasRepositoryProvider)
              .getById(id)
              .timeout(_detailTimeout);
          if (!mounted) return;
          _showSaleDetailDialog(sale);
          return;
        case 'service':
        case 'service_phase':
        case 'service_update':
          final service = await ref
              .read(operationsRepositoryProvider)
              .getService(id)
              .timeout(_detailTimeout);
          if (!mounted) return;
          _showServiceDetailDialog(service);
          return;
        default:
          _openEvent(event);
          return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir el detalle, abriendo módulo…\n$e'),
        ),
      );
      _openEvent(event);
    }
  }

  void _showCotizacionDetailDialog(CotizacionModel item) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle de cotización'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cliente: ${item.customerName}'),
                if ((item.customerPhone ?? '').trim().isNotEmpty)
                  Text('Teléfono: ${item.customerPhone}'),
                Text(
                  'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt)}',
                ),
                if (item.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Nota: ${item.note}'),
                ],
                const Divider(height: 18),
                ...item.items.map(
                  (line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line.nombre} x${line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(_formatMoney(line.total)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 18),
                Row(
                  children: [
                    const Expanded(child: Text('Subtotal')),
                    Text(_formatMoney(item.subtotal)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ITBIS ${item.includeItbis ? '(18%)' : '(no aplicado)'}',
                      ),
                    ),
                    Text(_formatMoney(item.itbisAmount)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      _formatMoney(item.total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showSaleDetailDialog(SaleModel sale) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final saleDate = sale.saleDate ?? DateTime.now();
        return AlertDialog(
          title: Text('Detalle de venta ${sale.id.substring(0, 8)}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailLine(
                    'Fecha',
                    DateFormat('dd/MM/yyyy HH:mm').format(saleDate),
                  ),
                  _detailLine('Cliente', sale.customerName ?? 'Sin cliente'),
                  _detailLine(
                    'Nota',
                    (sale.note ?? '').trim().isEmpty ? 'N/A' : sale.note!,
                  ),
                  const Divider(height: 20),
                  ...sale.items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.productNameSnapshot} x${item.qty}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(_formatMoney(item.subtotalSold)),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Text('Total vendido')),
                      Text(
                        _formatMoney(sale.totalSold),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('Comisión')),
                      Text(
                        _formatMoney(sale.commissionAmount),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _showServiceDetailDialog(ServiceModel service) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalle de servicio ${service.orderLabel}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailLine('Título', service.title),
                _detailLine('Categoría', service.category),
                _detailLine('Tipo', service.serviceType),
                _detailLine('Estado', service.status),
                _detailLine('Fase', service.currentPhase),
                _detailLine(
                  'Orden',
                  '${service.orderType} · ${service.orderState}',
                ),
                _detailLine('Prioridad', service.priority.toString()),
                if ((service.quotedAmount ?? 0) > 0)
                  _detailLine('Cotizado', _formatMoney(service.quotedAmount)),
                if ((service.depositAmount ?? 0) > 0)
                  _detailLine('Depósito', _formatMoney(service.depositAmount)),
                const Divider(height: 20),
                _detailLine('Cliente', service.customerName),
                if (service.customerPhone.trim().isNotEmpty)
                  _detailLine('Teléfono', service.customerPhone),
                const Divider(height: 20),
                _detailLine('Creado por', service.createdByName),
                if (service.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Descripción',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(service.description),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: const Text(
          '¿Seguro que deseas eliminar este cliente? Esta acción puede afectar el historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || _cliente == null) return;

    try {
      await ref.read(clientesControllerProvider.notifier).remove(_cliente!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).user;
    final profile = _profile;
    final metrics = profile?.metrics;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(
        title: const Text('Detalle del cliente'),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: _cliente == null
                ? null
                : () async {
                    final changed = await context.push<bool>(
                      Routes.clienteEdit(_cliente!.id),
                    );
                    if (changed == true) {
                      await _load();
                    }
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _cliente == null ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 56,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _cliente == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: _load,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                child: Text(
                                  _cliente!.nombre.trim().isEmpty
                                      ? '?'
                                      : _cliente!.nombre
                                            .trim()
                                            .characters
                                            .first
                                            .toUpperCase(),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _cliente!.nombre,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      _cliente!.telefono,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    if (metrics?.lastActivityAt != null)
                                      Text(
                                        'Última actividad: ${_formatDate(metrics?.lastActivityAt)}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _InfoCard(
                        icon: Icons.call_outlined,
                        title: 'Teléfono',
                        value: _cliente!.telefono,
                        trailing: IconButton(
                          tooltip: 'Copiar teléfono',
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await Clipboard.setData(
                              ClipboardData(text: _cliente!.telefono),
                            );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Teléfono copiado')),
                            );
                          },
                          icon: const Icon(Icons.copy_outlined),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _InfoCard(
                        icon: Icons.mail_outline,
                        title: 'Correo',
                        value: (_cliente!.correo ?? '').trim().isEmpty
                            ? 'Sin correo registrado'
                            : _cliente!.correo!,
                      ),
                      const SizedBox(height: 4),
                      _InfoCard(
                        icon: Icons.location_on_outlined,
                        title: 'Dirección',
                        value: (_cliente!.direccion ?? '').trim().isEmpty
                            ? 'Sin dirección registrada'
                            : _cliente!.direccion!,
                      ),
                      const SizedBox(height: 4),
                      _InfoCard(
                        icon: Icons.person_outline,
                        title: 'Creado por',
                        value:
                            _profile?.createdBy?.label ??
                            _profile?.client.ownerId ??
                            '—',
                      ),
                      const SizedBox(height: 4),
                      _InfoCard(
                        icon: Icons.calendar_month_outlined,
                        title: 'Creado el',
                        value: _formatDate(_profile?.client.createdAt),
                      ),
                      const SizedBox(height: 6),
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Métricas',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MetricTile(
                                      title: 'Ventas',
                                      count: metrics?.salesCount ?? 0,
                                      amount: _formatMoney(metrics?.salesTotal),
                                      subtitle:
                                          'Última: ${_formatDate(metrics?.lastSaleAt)}',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _MetricTile(
                                      title: 'Servicios',
                                      count: metrics?.servicesCount ?? 0,
                                      amount: null,
                                      subtitle:
                                          'Último: ${_formatDate(metrics?.lastServiceAt)}',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MetricTile(
                                      title: 'Cotizaciones',
                                      count: metrics?.cotizacionesCount ?? 0,
                                      amount: _formatMoney(
                                        metrics?.cotizacionesTotal,
                                      ),
                                      subtitle:
                                          'Última: ${_formatDate(metrics?.lastCotizacionAt)}',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _MetricTile(
                                      title: 'Actividad',
                                      count: _timeline.length,
                                      amount: null,
                                      subtitle: 'Cortesía del expediente',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Historial (expediente)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        context.go(Routes.operaciones),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Nuevo servicio'),
                                  ),
                                ],
                              ),
                              if (_timeline.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Este cliente no tiene actividad registrada',
                                  ),
                                )
                              else
                                ..._timeline.map((event) {
                                  final serviceTitle =
                                      (event.meta['serviceTitle'] ?? '')
                                          .toString()
                                          .trim();
                                  final status = (event.status ?? '').trim();
                                  final header = <String>[
                                    _formatDate(event.at),
                                    (event.userName ?? '').trim().isEmpty
                                        ? 'Sistema'
                                        : event.userName!.trim(),
                                    if (status.isNotEmpty) status,
                                  ].join(' · ');

                                  final subtitle = serviceTitle.isEmpty
                                      ? header
                                      : '$serviceTitle\n$header';

                                  return ListTile(
                                    dense: true,
                                    visualDensity: const VisualDensity(
                                      horizontal: -2,
                                      vertical: -3,
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      _iconForType(event.eventType),
                                      color: theme.colorScheme.primary,
                                    ),
                                    title: Text(event.title),
                                    subtitle: Text(subtitle),
                                    isThreeLine: serviceTitle.isNotEmpty,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (event.amount != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: Text(
                                              _formatMoney(event.amount),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        IconButton(
                                          tooltip: 'Ver detalle',
                                          onPressed: () => unawaited(
                                            _openEventDetail(event),
                                          ),
                                          icon: const Icon(Icons.open_in_new),
                                        ),
                                      ],
                                    ),
                                    onTap: () => _openEvent(event),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final changed = await context.push<bool>(
                                  Routes.clienteEdit(_cliente!.id),
                                );
                                if (changed == true) {
                                  await _load();
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _delete,
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Eliminar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final int count;
  final String? amount;
  final String subtitle;

  const _MetricTile({
    required this.title,
    required this.count,
    required this.amount,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (amount != null) ...[
            const SizedBox(height: 2),
            Text(
              amount!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Widget? trailing;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          title,
          style: theme.textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          value,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing,
      ),
    );
  }
}
