import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/route_access.dart';
import '../../core/routing/routes.dart';
import 'data/document_flows_repository.dart';
import 'document_flow_models.dart';

class DocumentFlowsScreen extends ConsumerStatefulWidget {
  const DocumentFlowsScreen({super.key});

  @override
  ConsumerState<DocumentFlowsScreen> createState() =>
      _DocumentFlowsScreenState();
}

class _DocumentFlowsScreenState extends ConsumerState<DocumentFlowsScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<OrderDocumentFlowModel> _flows = const [];
  _PrimaryDocumentFilter _activePrimaryFilter = _PrimaryDocumentFilter.all;
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
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(_dialogClearSentinel),
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
        drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
        appBar: const CustomAppBar(
          title: 'Flujo documental',
          showLogo: false,
          showDepartmentLabel: false,
        ),
        body: _AccessDeniedState(
          onGoHome: () => context.go(RouteAccess.defaultHomeForRole(role)),
        ),
      );
    }

    final filtered = _filteredFlows();
    final grouped = <DocumentFlowStatus, List<OrderDocumentFlowModel>>{};
    for (final flow in filtered) {
      grouped
          .putIfAbsent(flow.status, () => <OrderDocumentFlowModel>[])
          .add(flow);
    }

    final isDesktop = MediaQuery.of(context).size.width >= 920;
    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
      appBar: CustomAppBar(
        title: 'Flujo documental',
        showLogo: false,
        showDepartmentLabel: false,
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
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isDesktop ? 1060 : double.infinity,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _FiltersPanel(
                              controller: _searchController,
                              filterLabel:
                                  _selectedStatus?.label ?? 'Más filtros',
                              filterActive: _selectedStatus != null,
                              onOpenMobileFilter: _openMobileFilterDialog,
                              onClear: () {
                                setState(() {
                                  _activePrimaryFilter =
                                      _PrimaryDocumentFilter.all;
                                  _selectedStatus = null;
                                  _searchController.clear();
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _PrimaryFiltersRow(
                              selectedFilter: _activePrimaryFilter,
                              onChanged: (value) {
                                setState(() {
                                  _activePrimaryFilter = value;
                                  _selectedStatus = null;
                                });
                              },
                            ),
                            const SizedBox(height: 14),
                            if (filtered.isEmpty)
                              _FeedbackPanel(
                                icon: Icons.inbox_outlined,
                                title: 'No hay resultados para mostrar',
                                message: _selectedStatus == null
                                    ? 'No hay flujos documentales que coincidan con la búsqueda actual. Ajusta la búsqueda o cambia los filtros para ver otros documentos.'
                                    : 'No hay resultados para el filtro avanzado seleccionado. Ajusta la búsqueda o limpia el filtro.',
                              )
                            else
                              ...DocumentFlowStatus.values
                                  .where(
                                    (status) =>
                                        grouped[status]?.isNotEmpty ?? false,
                                  )
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
                  ],
                ),
        ),
      ),
    );
  }

  List<OrderDocumentFlowModel> _filteredFlows() {
    final query = _normalizeSearch(_searchController.text);
    final visibleStatuses = _selectedStatus != null
        ? <DocumentFlowStatus>{_selectedStatus!}
        : _activePrimaryFilter.statuses;

    return _flows
        .where((flow) {
          if (!visibleStatuses.contains(flow.status)) {
            return false;
          }

          if (query.isEmpty) return true;

          final clientName = _normalizeSearch(flow.order.client.nombre);
          final orderId = _normalizeSearch(flow.order.id);
          return clientName.contains(query) || orderId.contains(query);
        })
        .toList(growable: false);
  }
}

enum _PrimaryDocumentFilter { all, unsent, finalization, sent }

extension _PrimaryDocumentFilterX on _PrimaryDocumentFilter {
  String get label {
    switch (this) {
      case _PrimaryDocumentFilter.all:
        return 'Todos';
      case _PrimaryDocumentFilter.unsent:
        return 'No enviadas';
      case _PrimaryDocumentFilter.finalization:
        return 'Finalización';
      case _PrimaryDocumentFilter.sent:
        return 'Enviadas';
    }
  }

  Set<DocumentFlowStatus> get statuses {
    switch (this) {
      case _PrimaryDocumentFilter.all:
        return DocumentFlowStatus.values.toSet();
      case _PrimaryDocumentFilter.unsent:
        return {
          DocumentFlowStatus.pendingPreparation,
          DocumentFlowStatus.readyForReview,
          DocumentFlowStatus.readyForFinalization,
          DocumentFlowStatus.approved,
          DocumentFlowStatus.rejected,
        };
      case _PrimaryDocumentFilter.finalization:
        return {DocumentFlowStatus.readyForFinalization};
      case _PrimaryDocumentFilter.sent:
        return {DocumentFlowStatus.sent};
    }
  }

  Color get color {
    switch (this) {
      case _PrimaryDocumentFilter.all:
        return const Color(0xFF1F2937);
      case _PrimaryDocumentFilter.unsent:
        return const Color(0xFF0F5D73);
      case _PrimaryDocumentFilter.finalization:
        return const Color(0xFF6D28D9);
      case _PrimaryDocumentFilter.sent:
        return const Color(0xFF1D4ED8);
    }
  }
}

class _PrimaryFiltersRow extends StatelessWidget {
  const _PrimaryFiltersRow({
    required this.selectedFilter,
    required this.onChanged,
  });

  final _PrimaryDocumentFilter selectedFilter;
  final ValueChanged<_PrimaryDocumentFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _PrimaryDocumentFilter.values
            .map(
              (filter) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _PrimaryFilterChip(
                  filter: filter,
                  selected: filter == selectedFilter,
                  onTap: () => onChanged(filter),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _PrimaryFilterChip extends StatelessWidget {
  const _PrimaryFilterChip({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final _PrimaryDocumentFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? filter.color.withValues(alpha: 0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? filter.color.withValues(alpha: 0.30)
                  : const Color(0xFFD8E2EB),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: filter.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? filter.color : const Color(0xFF24303F),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.controller,
    required this.filterLabel,
    required this.filterActive,
    required this.onOpenMobileFilter,
    required this.onClear,
  });

  final TextEditingController controller;
  final String filterLabel;
  final bool filterActive;
  final VoidCallback onOpenMobileFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 760;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDEE5EC)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Buscar por cliente u orden',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: controller.text.trim().isEmpty && !filterActive
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Limpiar búsqueda y filtro',
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF7F9FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                hintStyle: const TextStyle(
                  fontSize: 12.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _MobileFilterButton(
            active: filterActive,
            compact: compact,
            label: compact ? null : filterLabel,
            onTap: onOpenMobileFilter,
          ),
        ],
      ),
    );
  }
}

class _MobileFilterButton extends StatelessWidget {
  const _MobileFilterButton({
    required this.active,
    required this.onTap,
    this.compact = true,
    this.label,
  });

  final bool active;
  final VoidCallback onTap;
  final bool compact;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0xFFEAF1FF) : const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: compact ? 46 : null,
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? const Color(0xFF315EFB) : const Color(0xFFD6DEE8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.tune,
                size: 16,
                color: active
                    ? const Color(0xFF315EFB)
                    : const Color(0xFF425466),
              ),
              if (!compact && label != null) ...[
                const SizedBox(width: 8),
                Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active
                        ? const Color(0xFF315EFB)
                        : const Color(0xFF425466),
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
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

class _DocumentFlowSection extends StatelessWidget {
  const _DocumentFlowSection({required this.status, required this.flows});

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
                decoration: BoxDecoration(
                  color: tone.color,
                  shape: BoxShape.circle,
                ),
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
          Column(
            children: flows
                .map(
                  (flow) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DocumentFlowCard(flow: flow),
                  ),
                )
                .toList(growable: false),
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
    final isCompact = MediaQuery.of(context).size.width < 760;
    final orderCode = flow.order.id.length >= 8
        ? flow.order.id.substring(0, 8).toUpperCase()
        : flow.order.id.toUpperCase();
    final sent = flow.sentAt != null;
    final invoiceReady = (flow.invoiceFinalUrl ?? '').trim().isNotEmpty;
    final warrantyReady = (flow.warrantyFinalUrl ?? '').trim().isNotEmpty;
    final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
    final lastEvent = flow.sentAt ?? flow.updatedAt ?? flow.createdAt;
    final detailParts = <String>[
      'Orden $orderCode',
      flow.order.serviceType,
      flow.order.category,
      if (flow.order.client.telefono.trim().isNotEmpty)
        flow.order.client.telefono.trim(),
      sent
          ? 'Enviado'
          : invoiceReady && warrantyReady
          ? 'Listo para envío'
          : 'En proceso',
      if (lastEvent != null) dateFmt.format(lastEvent),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go(Routes.documentFlowByOrderId(flow.orderId)),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFD8E2EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F0A2430),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: isCompact ? 72 : 76,
                decoration: BoxDecoration(
                  color: tone.color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(15),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 10 : 12,
                    isCompact ? 9 : 10,
                    isCompact ? 10 : 12,
                    isCompact ? 9 : 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    flow.order.client.nombre,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: isCompact ? 13.2 : 13.8,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF1F2A37),
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _StatusPill(
                                  label: flow.status.label,
                                  tone: tone,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detailParts.join('   ·   '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isCompact ? 10.5 : 10.9,
                                height: 1.1,
                                color: const Color(0xFF667085),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CompactFlag(
                            label: 'FAC',
                            active: invoiceReady,
                            activeColor: const Color(0xFF315EFB),
                          ),
                          const SizedBox(width: 6),
                          _CompactFlag(
                            label: 'GAR',
                            active: warrantyReady,
                            activeColor: const Color(0xFF0F766E),
                          ),
                          const SizedBox(width: 6),
                          _CompactFlag(
                            label: 'ENV',
                            active: sent,
                            activeColor: const Color(0xFF18794E),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Color(0xFF8A94A6),
                          ),
                        ],
                      ),
                    ],
                  ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          fontSize: 10.1,
        ),
      ),
    );
  }
}

class _CompactFlag extends StatelessWidget {
  const _CompactFlag({
    required this.label,
    required this.active,
    required this.activeColor,
  });

  final String label;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? activeColor.withValues(alpha: 0.12)
            : const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? activeColor.withValues(alpha: 0.26)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? activeColor : const Color(0xFF7B8794),
          fontWeight: FontWeight.w800,
          fontSize: 9.4,
          letterSpacing: 0.25,
        ),
      ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1E8EF)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: const Color(0xFF5B6B7F)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF112132),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Color(0xFF5B6B7F),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
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
            message:
                'Esta pantalla solo está disponible para administradores y asistentes.',
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
