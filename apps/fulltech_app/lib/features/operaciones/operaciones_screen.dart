import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/widgets/app_drawer.dart';
import 'application/operations_controller.dart';
import 'operations_models.dart';

class OperacionesScreen extends ConsumerStatefulWidget {
  const OperacionesScreen({super.key});

  @override
  ConsumerState<OperacionesScreen> createState() => _OperacionesScreenState();
}

class _OperacionesScreenState extends ConsumerState<OperacionesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchCtrl = TextEditingController();
  String? _selectedServiceId;

  static const _statuses = [
    'reserved',
    'survey',
    'scheduled',
    'in_progress',
    'completed',
    'warranty',
    'closed',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(operationsControllerProvider);
    final notifier = ref.read(operationsControllerProvider.notifier);
    final user = ref.watch(authStateProvider).user;

    return Scaffold(
      drawer: AppDrawer(currentUser: user),
      appBar: AppBar(
        title: const Text('Operaciones'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Tablero'),
            Tab(text: 'Nueva reserva'),
            Tab(text: 'Agenda'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Rango de fechas',
            onPressed: () async {
              final currentFrom = state.from ?? DateTime.now();
              final currentTo = state.to ?? currentFrom;
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
                initialDateRange: DateTimeRange(
                  start: currentFrom,
                  end: currentTo,
                ),
              );
              if (range == null) return;
              await notifier.setRange(range.start, range.end);
            },
            icon: const Icon(Icons.date_range_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _KpiHeader(state: state),
          if (state.loading) const LinearProgressIndicator(),
          if (state.error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(10),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBoard(context, state, notifier),
                _CreateReservationTab(onCreate: _handleCreateService),
                _AgendaTab(
                  services: state.services,
                  onOpenService: _openServiceDetail,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(
    BuildContext context,
    OperationsState state,
    OperationsController notifier,
  ) {
    final selected = _selectedServiceId == null
        ? null
        : state.services
            .where((item) => item.id == _selectedServiceId)
            .cast<ServiceModel?>()
            .firstWhere((_) => true, orElse: () => null);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 900;
        final wide = constraints.maxWidth >= 1100;

        Widget buildStatusColumn(String status, {double? width, double height = 300}) {
          final items = state.services.where((service) => service.status == status).toList();
          return SizedBox(
            width: width,
            height: height,
            child: _KanbanColumn(
              title: _labelStatus(status),
              count: items.length,
              services: items,
              onOpen: (service) {
                setState(() => _selectedServiceId = service.id);
                if (!wide) {
                  _openServiceDetail(service);
                }
              },
            ),
          );
        }

        final board = RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
            children: [
              _FiltersBar(
                searchCtrl: _searchCtrl,
                state: state,
                onSearch: notifier.setSearch,
                onStatus: notifier.setStatus,
                onType: notifier.setType,
                onPriority: notifier.setPriority,
              ),
              const SizedBox(height: 10),
              if (mobile)
                ..._statuses.map(
                  (status) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: buildStatusColumn(status, height: 250),
                  ),
                )
              else
                SizedBox(
                  height: wide ? constraints.maxHeight - 90 : 520,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _statuses.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final status = _statuses[index];
                      return buildStatusColumn(status, width: 290, height: wide ? constraints.maxHeight - 110 : 500);
                    },
                  ),
                ),
            ],
          ),
        );

        if (!wide) return board;

        return Row(
          children: [
            Expanded(flex: 6, child: board),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 4,
              child: selected == null
                  ? const Center(child: Text('Selecciona un servicio para ver detalle'))
                  : _ServiceDetailPanel(
                      service: selected,
                      onChangeStatus: (status) => _changeStatus(selected.id, status),
                      onSchedule: (start, end) =>
                          _scheduleService(selected.id, start, end),
                      onCreateWarranty: () => _createWarranty(selected.id),
                      onAssign: (assignments) => _assignTechs(selected.id, assignments),
                      onToggleStep: (stepId, done) =>
                          _toggleStep(selected.id, stepId, done),
                      onAddNote: (message) => _addNote(selected.id, message),
                      onUploadEvidence: () => _uploadEvidence(selected.id),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openServiceDetail(ServiceModel service) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: _ServiceDetailPanel(
              service: service,
              onChangeStatus: (status) => _changeStatus(service.id, status),
              onSchedule: (start, end) => _scheduleService(service.id, start, end),
              onCreateWarranty: () => _createWarranty(service.id),
              onAssign: (assignments) => _assignTechs(service.id, assignments),
              onToggleStep: (stepId, done) => _toggleStep(service.id, stepId, done),
              onAddNote: (message) => _addNote(service.id, message),
              onUploadEvidence: () => _uploadEvidence(service.id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleCreateService(_CreateServiceDraft draft) async {
    try {
      await ref.read(operationsControllerProvider.notifier).createReservation(
            customerId: draft.customerId,
            serviceType: draft.serviceType,
            category: draft.category,
            priority: draft.priority,
            title: draft.title,
            description: draft.description,
            addressSnapshot: draft.addressSnapshot,
            quotedAmount: draft.quotedAmount,
            depositAmount: draft.depositAmount,
          );

      if (!mounted) return;
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reserva creada correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'No se pudo crear la reserva',
          ),
        ),
      );
    }
  }

  Future<void> _changeStatus(String serviceId, String status) async {
    try {
      await ref.read(operationsControllerProvider.notifier).changeStatus(serviceId, status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _scheduleService(String id, DateTime start, DateTime end) async {
    try {
      await ref.read(operationsControllerProvider.notifier).schedule(id, start, end);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _createWarranty(String id) async {
    try {
      await ref.read(operationsControllerProvider.notifier).createWarranty(id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _toggleStep(String id, String stepId, bool done) async {
    try {
      await ref.read(operationsControllerProvider.notifier).toggleStep(id, stepId, done);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _addNote(String id, String note) async {
    try {
      await ref.read(operationsControllerProvider.notifier).addNote(id, note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _assignTechs(String id, List<Map<String, String>> assignments) async {
    try {
      await ref.read(operationsControllerProvider.notifier).assign(id, assignments);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  Future<void> _uploadEvidence(String id) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    try {
      await ref
          .read(operationsControllerProvider.notifier)
          .uploadEvidence(id, result.files.first);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Evidencia subida')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  String _labelStatus(String status) {
    const map = {
      'reserved': 'Reserva',
      'survey': 'Levantamiento',
      'scheduled': 'Agendado',
      'in_progress': 'En proceso',
      'completed': 'Finalizada',
      'warranty': 'Garantía',
      'closed': 'Cerrada',
      'cancelled': 'Cancelada',
    };
    return map[status] ?? status;
  }
}

class _KpiHeader extends StatelessWidget {
  final OperationsState state;

  const _KpiHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final dash = state.dashboard;
    final inProgress = dash.activeByStatus['in_progress'] ?? 0;
    final items = [
      _miniKpi('Activos', '$inProgress'),
      _miniKpi('Instalaciones hoy', '${dash.installationsPendingToday}'),
      _miniKpi('Garantías', '${dash.warrantiesOpen}'),
      _miniKpi('Promedio (h)', dash.averageHoursByLifecycle.toStringAsFixed(1)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final cardWidth = compact ? (constraints.maxWidth - 28) / 2 : (constraints.maxWidth - 44) / 4;

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((item) => SizedBox(width: cardWidth, child: item))
                .toList(),
          ),
        );
      },
    );
  }

  Widget _miniKpi(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final OperationsState state;
  final Future<void> Function(String) onSearch;
  final Future<void> Function(String?) onStatus;
  final Future<void> Function(String?) onType;
  final Future<void> Function(int?) onPriority;

  const _FiltersBar({
    required this.searchCtrl,
    required this.state,
    required this.onSearch,
    required this.onStatus,
    required this.onType,
    required this.onPriority,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar cliente, teléfono, ticket',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Aplicar',
                onPressed: () => onSearch(searchCtrl.text),
                icon: const Icon(Icons.check),
              ),
            ),
            onSubmitted: onSearch,
          ),
        ),
        DropdownButton<String?>(
          value: state.statusFilter,
          hint: const Text('Estado'),
          items: const [
            DropdownMenuItem<String?>(value: null, child: Text('Todos')),
            DropdownMenuItem(value: 'reserved', child: Text('Reserva')),
            DropdownMenuItem(value: 'survey', child: Text('Levantamiento')),
            DropdownMenuItem(value: 'scheduled', child: Text('Agendado')),
            DropdownMenuItem(value: 'in_progress', child: Text('En proceso')),
            DropdownMenuItem(value: 'completed', child: Text('Finalizada')),
            DropdownMenuItem(value: 'warranty', child: Text('Garantía')),
            DropdownMenuItem(value: 'closed', child: Text('Cerrada')),
          ],
          onChanged: onStatus,
        ),
        DropdownButton<String?>(
          value: state.typeFilter,
          hint: const Text('Tipo'),
          items: const [
            DropdownMenuItem<String?>(value: null, child: Text('Todos')),
            DropdownMenuItem(value: 'installation', child: Text('Instalación')),
            DropdownMenuItem(value: 'maintenance', child: Text('Mantenimiento')),
            DropdownMenuItem(value: 'warranty', child: Text('Garantía')),
            DropdownMenuItem(value: 'pos_support', child: Text('Soporte POS')),
            DropdownMenuItem(value: 'other', child: Text('Otros')),
          ],
          onChanged: onType,
        ),
        DropdownButton<int?>(
          value: state.priorityFilter,
          hint: const Text('Prioridad'),
          items: const [
            DropdownMenuItem<int?>(value: null, child: Text('Todas')),
            DropdownMenuItem(value: 1, child: Text('Alta')),
            DropdownMenuItem(value: 2, child: Text('Media')),
            DropdownMenuItem(value: 3, child: Text('Baja')),
          ],
          onChanged: onPriority,
        ),
      ],
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String title;
  final int count;
  final List<ServiceModel> services;
  final void Function(ServiceModel) onOpen;

  const _KanbanColumn({
    required this.title,
    required this.count,
    required this.services,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$title ($count)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: services.isEmpty
                  ? const Center(child: Text('Sin tickets'))
                  : ListView.separated(
                      itemCount: services.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final service = services[index];
                        return InkWell(
                          onTap: () => onOpen(service),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Theme.of(context).dividerColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(service.customerPhone),
                                const SizedBox(height: 4),
                                Text('${service.serviceType} · ${service.category}'),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _badge('P${service.priority}'),
                                    _badge(service.status),
                                  ],
                                ),
                                if (service.scheduledStart != null) ...[
                                  const SizedBox(height: 4),
                                  Text('Agenda: ${dateFormat.format(service.scheduledStart!)}'),
                                ],
                                if (service.assignments.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    service.assignments
                                        .map((assignment) => assignment.userName)
                                        .join(', '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(width: 0.7),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _ServiceDetailPanel extends StatefulWidget {
  final ServiceModel service;
  final Future<void> Function(String status) onChangeStatus;
  final Future<void> Function(DateTime start, DateTime end) onSchedule;
  final Future<void> Function() onCreateWarranty;
  final Future<void> Function(List<Map<String, String>> assignments) onAssign;
  final Future<void> Function(String stepId, bool done) onToggleStep;
  final Future<void> Function(String message) onAddNote;
  final Future<void> Function() onUploadEvidence;

  const _ServiceDetailPanel({
    required this.service,
    required this.onChangeStatus,
    required this.onSchedule,
    required this.onCreateWarranty,
    required this.onAssign,
    required this.onToggleStep,
    required this.onAddNote,
    required this.onUploadEvidence,
  });

  @override
  State<_ServiceDetailPanel> createState() => _ServiceDetailPanelState();
}

class _ServiceDetailPanelState extends State<_ServiceDetailPanel> {
  final _noteCtrl = TextEditingController();
  final _techCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    _techCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final nextStatuses = const [
      'survey',
      'scheduled',
      'in_progress',
      'completed',
      'warranty',
      'closed',
      'cancelled',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(service.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('${service.customerName} · ${service.customerPhone}'),
        Text('${service.serviceType} · ${service.category} · P${service.priority}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DropdownButton<String>(
              value: service.status,
              items: nextStatuses
                  .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                widget.onChangeStatus(value);
              },
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                  initialDateRange: DateTimeRange(
                    start: service.scheduledStart ?? DateTime.now(),
                    end: service.scheduledEnd ?? DateTime.now().add(const Duration(hours: 2)),
                  ),
                );
                if (picked == null) return;
                await widget.onSchedule(
                  DateTime(
                    picked.start.year,
                    picked.start.month,
                    picked.start.day,
                    8,
                  ),
                  DateTime(
                    picked.end.year,
                    picked.end.month,
                    picked.end.day,
                    18,
                  ),
                );
              },
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Agendar/Reagendar'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final ids = await _askTechIds(context);
                if (ids == null || ids.isEmpty) return;
                await widget.onAssign(
                  ids
                      .map((id) => <String, String>{'userId': id, 'role': 'assistant'})
                      .toList(),
                );
              },
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Asignar técnicos'),
            ),
            if (service.status == 'completed' || service.status == 'closed')
              FilledButton.icon(
                onPressed: widget.onCreateWarranty,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Crear garantía'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => widget.onAddNote('Llegué al sitio'),
              child: const Text('Llegué al sitio'),
            ),
            OutlinedButton(
              onPressed: () => widget.onAddNote('Inicié trabajo'),
              child: const Text('Inicié'),
            ),
            OutlinedButton(
              onPressed: () => widget.onAddNote('Finalicé trabajo'),
              child: const Text('Finalicé'),
            ),
            OutlinedButton(
              onPressed: () async {
                final reason = await _askReason(context);
                if (reason == null || reason.trim().isEmpty) return;
                await widget.onAddNote('Pendiente por: ${reason.trim()}');
              },
              child: const Text('Pendiente por X'),
            ),
            FilledButton.icon(
              onPressed: widget.onUploadEvidence,
              icon: const Icon(Icons.attach_file),
              label: const Text('Subir evidencia'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('Datos del cliente'),
        Text(service.customerAddress.isEmpty ? 'Sin dirección' : service.customerAddress),
        const SizedBox(height: 10),
        _sectionTitle('Checklist'),
        ...service.steps.map(
          (step) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(step.stepLabel),
            subtitle: step.doneAt == null
                ? null
                : Text('Completado ${dateFormat.format(step.doneAt!)}'),
            value: step.isDone,
            onChanged: (value) {
              if (value == null) return;
              widget.onToggleStep(step.id, value);
            },
          ),
        ),
        const SizedBox(height: 10),
        _sectionTitle('Evidencias'),
        if (service.files.isEmpty)
          const Text('Sin evidencias todavía')
        else
          ...service.files.map(
            (file) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(file.fileType),
              subtitle: Text(file.fileUrl),
            ),
          ),
        const SizedBox(height: 10),
        _sectionTitle('Historial'),
        if (service.updates.isEmpty)
          const Text('Sin movimientos')
        else
          ...service.updates.take(8).map(
                (update) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(update.message.isEmpty ? update.type : update.message),
                  subtitle: Text(
                    '${update.changedBy} · ${update.createdAt == null ? '-' : dateFormat.format(update.createdAt!)}',
                  ),
                ),
              ),
        const SizedBox(height: 10),
        _sectionTitle('Notas internas'),
        TextField(
          controller: _noteCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Escribe una nota interna...',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () {
              final note = _noteCtrl.text.trim();
              if (note.isEmpty) return;
              widget.onAddNote(note);
              _noteCtrl.clear();
            },
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('Guardar nota'),
          ),
        ),
      ],
    );
  }

  Future<List<String>?> _askTechIds(BuildContext context) async {
    _techCtrl.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Asignar técnicos'),
        content: TextField(
          controller: _techCtrl,
          decoration: const InputDecoration(
            hintText: 'UUID1, UUID2, UUID3',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Asignar')),
        ],
      ),
    );
    if (ok != true) return null;
    final value = _techCtrl.text.trim();
    if (value.isEmpty) return null;
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<String?> _askReason(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motivo pendiente'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    return ok == true ? text : null;
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _AgendaTab extends StatelessWidget {
  final List<ServiceModel> services;
  final void Function(ServiceModel) onOpenService;

  const _AgendaTab({required this.services, required this.onOpenService});

  @override
  Widget build(BuildContext context) {
    final scheduled = services.where((item) => item.scheduledStart != null).toList()
      ..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
    final dateFormat = DateFormat('EEE dd/MM HH:mm', 'es');

    if (scheduled.isEmpty) {
      return const Center(child: Text('Sin servicios agendados en el rango seleccionado'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: scheduled.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final service = scheduled[index];
        final techs = service.assignments.map((a) => a.userName).join(', ');
        return Card(
          child: ListTile(
            onTap: () => onOpenService(service),
            title: Text('${service.customerName} · ${service.title}'),
            subtitle: Text(
              '${dateFormat.format(service.scheduledStart!)} · ${service.status}\n${techs.isEmpty ? 'Sin técnicos' : techs}',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(service.serviceType),
                Text('P${service.priority}'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CreateServiceDraft {
  final String customerId;
  final String serviceType;
  final String category;
  final int priority;
  final String title;
  final String description;
  final String? addressSnapshot;
  final double? quotedAmount;
  final double? depositAmount;

  _CreateServiceDraft({
    required this.customerId,
    required this.serviceType,
    required this.category,
    required this.priority,
    required this.title,
    required this.description,
    this.addressSnapshot,
    this.quotedAmount,
    this.depositAmount,
  });
}

class _CreateReservationTab extends ConsumerStatefulWidget {
  final Future<void> Function(_CreateServiceDraft draft) onCreate;

  const _CreateReservationTab({required this.onCreate});

  @override
  ConsumerState<_CreateReservationTab> createState() => _CreateReservationTabState();
}

class _CreateReservationTabState extends ConsumerState<_CreateReservationTab> {
  final _formKey = GlobalKey<FormState>();
  final _searchClientCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _quotedCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();

  String _serviceType = 'installation';
  String _category = 'cameras';
  int _priority = 1;
  String? _customerId;
  String? _customerName;
  bool _loadingClients = false;
  bool _saving = false;
  List<dynamic> _clients = [];

  @override
  void dispose() {
    _searchClientCtrl.dispose();
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _quotedCtrl.dispose();
    _depositCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          TextFormField(
            controller: _searchClientCtrl,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Cliente (buscar)',
              suffixIcon: IconButton(
                onPressed: _loadingClients ? null : _searchClients,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingClients) const LinearProgressIndicator(),
          if (_clients.isNotEmpty)
            Card(
              child: Column(
                children: _clients
                    .map(
                      (item) => ListTile(
                        title: Text(item.nombre),
                        subtitle: Text(item.telefono),
                        trailing: _customerId == item.id
                            ? const Icon(Icons.check_circle)
                            : null,
                        onTap: () {
                          setState(() {
                            _customerId = item.id;
                            _customerName = item.nombre;
                            _addressCtrl.text = item.direccion ?? '';
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          if (_customerName != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Cliente seleccionado: $_customerName'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _createQuickClient,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Crear cliente rápido'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _serviceType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Tipo de servicio',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'installation', child: Text('Instalación')),
                    DropdownMenuItem(value: 'maintenance', child: Text('Mantenimiento')),
                    DropdownMenuItem(value: 'pos_support', child: Text('Soporte POS')),
                    DropdownMenuItem(value: 'other', child: Text('Otro')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _serviceType = value;
                      if (value == 'installation') _priority = 1;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Categoría',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cameras', child: Text('Cámaras')),
                    DropdownMenuItem(value: 'gate_motor', child: Text('Motor de portón')),
                    DropdownMenuItem(value: 'alarm', child: Text('Alarma')),
                    DropdownMenuItem(value: 'electric_fence', child: Text('Cerco eléctrico')),
                    DropdownMenuItem(value: 'intercom', child: Text('Intercom')),
                    DropdownMenuItem(value: 'pos', child: Text('POS')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _priority,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Prioridad',
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Alta')),
              DropdownMenuItem(value: 2, child: Text('Media')),
              DropdownMenuItem(value: 3, child: Text('Baja')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _priority = value);
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Título',
            ),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Requerido' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _descriptionCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Descripción',
            ),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Requerido' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Dirección (snapshot)',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _quotedCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Monto cotizado',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _depositCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Abono',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Guardando...' : 'Guardar reserva'),
          ),
        ],
      ),
    );
  }

  Future<void> _searchClients() async {
    setState(() => _loadingClients = true);
    try {
      final results = await ref
          .read(operationsControllerProvider.notifier)
          .searchClients(_searchClientCtrl.text.trim());
      if (!mounted) return;
      setState(() => _clients = results);
    } finally {
      if (mounted) {
        setState(() => _loadingClients = false);
      }
    }
  }

  Future<void> _save() async {
    if (_customerId == null || _customerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente primero')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await widget.onCreate(
        _CreateServiceDraft(
          customerId: _customerId!,
          serviceType: _serviceType,
          category: _category,
          priority: _priority,
          title: _titleCtrl.text.trim(),
          description: _descriptionCtrl.text.trim(),
          addressSnapshot: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          quotedAmount: double.tryParse(_quotedCtrl.text.trim()),
          depositAmount: double.tryParse(_depositCtrl.text.trim()),
        ),
      );
      if (!mounted) return;
      _formKey.currentState!.reset();
      _titleCtrl.clear();
      _descriptionCtrl.clear();
      _addressCtrl.clear();
      _quotedCtrl.clear();
      _depositCtrl.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createQuickClient() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo cliente rápido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crear')),
        ],
      ),
    );

    if (ok != true) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      return;
    }

    try {
      final created = await ref
          .read(operationsControllerProvider.notifier)
          .createQuickClient(nombre: nameCtrl.text.trim(), telefono: phoneCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _customerId = created.id;
        _customerName = created.nombre;
        _addressCtrl.text = created.direccion ?? '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cliente creado y seleccionado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    }
  }
}
