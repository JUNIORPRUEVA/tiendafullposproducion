import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/route_access.dart';
import '../../core/routing/routes.dart';
import 'data/document_flows_repository.dart';
import 'document_flow_models.dart';

class DocumentFlowsScreen extends ConsumerStatefulWidget {
  const DocumentFlowsScreen({super.key});

  @override
  ConsumerState<DocumentFlowsScreen> createState() => _DocumentFlowsScreenState();
}

class _DocumentFlowsScreenState extends ConsumerState<DocumentFlowsScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<OrderDocumentFlowModel> _flows = const [];
  DocumentFlowStatus? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openMobileFilterDialog() async {
    var tempStatus = _selectedStatus;
    final result = await showDialog<DocumentFlowStatus?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Filtrar flujo documental'),
              content: DropdownButtonFormField<DocumentFlowStatus?>(
                initialValue: tempStatus,
                decoration: InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  const DropdownMenuItem<DocumentFlowStatus?>(
                    value: null,
                    child: Text('Todos los estados'),
                  ),
                  ...DocumentFlowStatus.values.map(
                    (status) => DropdownMenuItem<DocumentFlowStatus?>(
                      value: status,
                      child: Text(status.label),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setDialogState(() {
                    tempStatus = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(_dialogClearSentinel),
                  child: const Text('Limpiar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(tempStatus),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null && result != _dialogClearSentinel) return;

    setState(() {
      if (result == _dialogClearSentinel) {
        _selectedStatus = null;
      } else {
        _selectedStatus = result;
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final flows = await ref.read(documentFlowsRepositoryProvider).listFlows();
      if (!mounted) return;
      flows.sort((a, b) {
        final left = a.sentAt ?? a.updatedAt ?? a.createdAt ?? DateTime(2000);
        final right = b.sentAt ?? b.updatedAt ?? b.createdAt ?? DateTime(2000);
        return right.compareTo(left);
      });
      setState(() {
        _flows = flows;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el flujo documental';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final role = auth.user?.appRole ?? AppRole.unknown;
    final canView = role.isAdmin || role == AppRole.asistente;

    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('Flujo documental')),
        body: _AccessDeniedState(
          onGoHome: () => context.go(RouteAccess.defaultHomeForRole(role)),
        ),
      );
    }

    final filtered = _filteredFlows();
    final grouped = <DocumentFlowStatus, List<OrderDocumentFlowModel>>{};
    for (final flow in filtered) {
      grouped.putIfAbsent(flow.status, () => <OrderDocumentFlowModel>[]).add(flow);
    }

    final isDesktop = MediaQuery.of(context).size.width >= 920;
    final sentCount = filtered.where((flow) => flow.sentAt != null).length;
    final pendingSendCount = filtered.length - sentCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flujo documental'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFF4F7FA),
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 72),
                        _FeedbackPanel(
                          icon: Icons.error_outline,
                          title: 'No se pudo cargar el flujo documental',
                          message: _error!,
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 24 : 14,
                        12,
                        isDesktop ? 24 : 14,
                        18,
                      ),
                      children: [
                        _DocumentFlowsHero(
                          total: filtered.length,
                          sent: sentCount,
                          pending: pendingSendCount,
                        ),
                        const SizedBox(height: 10),
                        _FiltersPanel(
                          controller: _searchController,
                          selectedStatus: _selectedStatus,
                          onOpenMobileFilter: _openMobileFilterDialog,
                          onStatusChanged: (value) {
                            setState(() {
                              _selectedStatus = value;
                            });
                          },
                          onClear: () {
                            setState(() {
                              _selectedStatus = null;
                              _searchController.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        if (filtered.isEmpty)
                          const _FeedbackPanel(
                            icon: Icons.inbox_outlined,
                            title: 'No hay resultados para mostrar',
                            message: 'Ajusta el buscador o el filtro para encontrar otro cliente.',
                          )
                        else
                          ...DocumentFlowStatus.values
                              .where((status) => grouped[status]?.isNotEmpty ?? false)
                              .map(
                                (status) => _DocumentFlowSection(
                                  status: status,
                                  flows: grouped[status]!,
                                ),
                              ),
                      ],
                    ),
        ),
      ),
    );
  }

  List<OrderDocumentFlowModel> _filteredFlows() {
    final query = _normalizeSearch(_searchController.text);
    return _flows.where((flow) {
      if (_selectedStatus != null && flow.status != _selectedStatus) {
        return false;
      }

      if (query.isEmpty) return true;

      final clientName = _normalizeSearch(flow.order.client.nombre);
      final orderId = _normalizeSearch(flow.order.id);
      return clientName.contains(query) || orderId.contains(query);
    }).toList(growable: false);
  }
}

class _DocumentFlowsHero extends StatelessWidget {
  const _DocumentFlowsHero({
    required this.total,
    required this.sent,
    required this.pending,
  });

  final int total;
  final int sent;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 760;
    final isMobile = !isDesktop;
    final metrics = [
      _HeroMetric(
        title: 'Flujos visibles',
        value: '$total',
        subtitle: 'Seguimiento documental activo',
        color: const Color(0xFF0E5A6A),
        compact: isMobile,
      ),
      _HeroMetric(
        title: 'Enviados',
        value: '$sent',
        subtitle: 'Clientes con documentación enviada',
        color: const Color(0xFF18794E),
        compact: isMobile,
      ),
      _HeroMetric(
        title: 'Pendientes',
        value: '$pending',
        subtitle: 'Casos aún no despachados',
        color: const Color(0xFFB26B00),
        compact: isMobile,
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E5A6A), Color(0xFF1B7283)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160A2430),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: isDesktop
          ? Row(
              children: metrics
                  .map(
                    (metric) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: metric,
                      ),
                    ),
                  )
                  .toList(growable: false),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: metrics,
            ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    this.compact = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 10,
      ),
      constraints: compact ? null : const BoxConstraints(minHeight: 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 999 : 14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.controller,
    required this.selectedStatus,
    required this.onOpenMobileFilter,
    required this.onStatusChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final DocumentFlowStatus? selectedStatus;
  final VoidCallback onOpenMobileFilter;
  final ValueChanged<DocumentFlowStatus?> onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 760;
    final filterField = DropdownButtonFormField<DocumentFlowStatus?>(
      initialValue: selectedStatus,
      decoration: InputDecoration(
        labelText: 'Filtrar por estado',
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.tune),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD6DEE8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD6DEE8)),
        ),
      ),
      items: [
        const DropdownMenuItem<DocumentFlowStatus?>(
          value: null,
          child: Text('Todos los estados'),
        ),
        ...DocumentFlowStatus.values.map(
          (status) => DropdownMenuItem<DocumentFlowStatus?>(
            value: status,
            child: Text(status.label),
          ),
        ),
      ],
      onChanged: onStatusChanged,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDEE5EC)),
      ),
      child: isDesktop
          ? Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                        hintText: 'Buscar por cliente u orden',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: const Color(0xFFF7F9FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(flex: 3, child: filterField),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                  label: const Text('Limpiar'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'Buscar por cliente u orden',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: controller.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () => controller.clear(),
                                  icon: const Icon(Icons.close),
                                ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _MobileFilterButton(
                      active: selectedStatus != null,
                      onTap: onOpenMobileFilter,
                    ),
                  ],
                ),
                if (selectedStatus != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F9FC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD6DEE8)),
                          ),
                          child: Text(
                            'Filtro: ${selectedStatus!.label}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF425466),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: onClear,
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _MobileFilterButton extends StatelessWidget {
  const _MobileFilterButton({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFFEAF1FF) : const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? const Color(0xFF315EFB) : const Color(0xFFD6DEE8),
            ),
          ),
          child: Icon(
            Icons.tune,
            color: active ? const Color(0xFF315EFB) : const Color(0xFF425466),
          ),
        ),
      ),
    );
  }
}

class _DocumentFlowSection extends StatelessWidget {
  const _DocumentFlowSection({
    required this.status,
    required this.flows,
  });

  final DocumentFlowStatus status;
  final List<OrderDocumentFlowModel> flows;

  @override
  Widget build(BuildContext context) {
    final tone = _statusTone(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                status.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: const Color(0xFF24303F),
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.soft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${flows.length}',
                  style: TextStyle(
                    color: tone.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWideDesktop = constraints.maxWidth >= 1220;
              final isDesktop = constraints.maxWidth >= 920;
              final isTablet = constraints.maxWidth >= 620;
              final spacing = 10.0;
              final columns = isWideDesktop ? 3 : (isDesktop ? 2 : (isTablet ? 2 : 1));
              final cardWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: flows
                    .map(
                      (flow) => SizedBox(
                        width: cardWidth,
                        child: _DocumentFlowCard(flow: flow),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DocumentFlowCard extends StatelessWidget {
  const _DocumentFlowCard({required this.flow});

  final OrderDocumentFlowModel flow;

  @override
  Widget build(BuildContext context) {
    final tone = _statusTone(flow.status);
    final orderCode = flow.order.id.length >= 8
        ? flow.order.id.substring(0, 8).toUpperCase()
        : flow.order.id.toUpperCase();
    final sent = flow.sentAt != null;
    final invoiceReady = (flow.invoiceFinalUrl ?? '').trim().isNotEmpty;
    final warrantyReady = (flow.warrantyFinalUrl ?? '').trim().isNotEmpty;
    final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
    final lastEvent = flow.sentAt ?? flow.updatedAt ?? flow.createdAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go(Routes.documentFlowByOrderId(flow.orderId)),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDE5ED)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120A2430),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: tone.color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                flow.order.client.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.2,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1F2A37),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Orden $orderCode · ${flow.order.serviceType} · ${flow.order.category}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.2,
                                  height: 1.2,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(label: flow.status.label, tone: tone),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniBadge(
                          icon: sent ? Icons.mark_email_read_outlined : Icons.schedule_send_outlined,
                          label: sent ? 'Documentos enviados' : 'Pendiente de envío',
                          background: sent ? const Color(0xFFE9F8EF) : const Color(0xFFFFF4E5),
                          foreground: sent ? const Color(0xFF18794E) : const Color(0xFFB26B00),
                        ),
                        _MiniBadge(
                          icon: invoiceReady ? Icons.receipt_long_outlined : Icons.receipt_outlined,
                          label: invoiceReady ? 'Factura lista' : 'Factura pendiente',
                          background: invoiceReady ? const Color(0xFFEAF1FF) : const Color(0xFFF4F6F8),
                          foreground: invoiceReady ? const Color(0xFF315EFB) : const Color(0xFF667085),
                        ),
                        _MiniBadge(
                          icon: warrantyReady ? Icons.verified_outlined : Icons.shield_outlined,
                          label: warrantyReady ? 'Garantía lista' : 'Garantía pendiente',
                          background: warrantyReady ? const Color(0xFFE8F7F7) : const Color(0xFFF4F6F8),
                          foreground: warrantyReady ? const Color(0xFF0F766E) : const Color(0xFF667085),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5EAF0)),
                      ),
                      child: Column(
                        children: [
                          _MetaLine(
                            label: 'Cliente',
                            value: flow.order.client.telefono.trim().isEmpty
                                ? flow.order.client.nombre
                                : '${flow.order.client.nombre} · ${flow.order.client.telefono}',
                          ),
                          const SizedBox(height: 6),
                          _MetaLine(
                            label: 'Estado de envío',
                            value: sent ? 'Enviado al cliente' : 'Aún no enviado',
                            valueColor: sent ? const Color(0xFF18794E) : const Color(0xFFB26B00),
                          ),
                          if (lastEvent != null) ...[
                            const SizedBox(height: 6),
                            _MetaLine(
                              label: sent ? 'Enviado el' : 'Actualizado el',
                              value: dateFmt.format(lastEvent),
                            ),
                          ],
                        ],
                      ),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tone.color,
          fontWeight: FontWeight.w700,
          fontSize: 10.8,
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF667085),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11.4,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF24303F),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDEE5EC)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: const Color(0xFF667085)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF24303F),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Color(0xFF667085),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

class _AccessDeniedState extends StatelessWidget {
  const _AccessDeniedState({required this.onGoHome});

  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: _FeedbackPanel(
            icon: Icons.lock_outline,
            title: 'Acceso restringido',
            message: 'Esta pantalla solo está disponible para administradores y asistentes.',
            action: ElevatedButton.icon(
              onPressed: onGoHome,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusTone {
  const _StatusTone({
    required this.color,
    required this.soft,
    required this.border,
  });

  final Color color;
  final Color soft;
  final Color border;
}

_StatusTone _statusTone(DocumentFlowStatus status) {
  switch (status) {
    case DocumentFlowStatus.approved:
      return const _StatusTone(
        color: Color(0xFF18794E),
        soft: Color(0xFFE9F8EF),
        border: Color(0xFFC8EAD6),
      );
    case DocumentFlowStatus.sent:
      return const _StatusTone(
        color: Color(0xFF1D4ED8),
        soft: Color(0xFFEAF1FF),
        border: Color(0xFFCAD8FF),
      );
    case DocumentFlowStatus.readyForFinalization:
      return const _StatusTone(
        color: Color(0xFF6D28D9),
        soft: Color(0xFFF2EAFF),
        border: Color(0xFFE0D0FF),
      );
    case DocumentFlowStatus.readyForReview:
      return const _StatusTone(
        color: Color(0xFFB26B00),
        soft: Color(0xFFFFF4E5),
        border: Color(0xFFF0D5A4),
      );
    case DocumentFlowStatus.pendingPreparation:
      return const _StatusTone(
        color: Color(0xFF0F5D73),
        soft: Color(0xFFE8F5F8),
        border: Color(0xFFCAE6EC),
      );
    case DocumentFlowStatus.rejected:
      return const _StatusTone(
        color: Color(0xFFB42318),
        soft: Color(0xFFFDECEC),
        border: Color(0xFFF3CACA),
      );
  }
}

String _normalizeSearch(String value) => value.trim().toLowerCase();

const _dialogClearSentinel = Object();