import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/crm_comercial_repository.dart';
import 'models/crm_comercial_models.dart';

const List<String> _crmStatuses = <String>[
  'NUEVO',
  'INTERESADO',
  'COTIZACION',
  'NEGOCIACION',
  'PENDIENTE_PAGO',
  'GANADO',
  'PERDIDO',
  'SEGUIMIENTO',
  'SOPORTE',
  'COBRO_PENDIENTE',
];

const List<String> _taskPriorities = <String>['BAJA', 'NORMAL', 'ALTA', 'URGENTE'];

class CrmComercialScreen extends ConsumerStatefulWidget {
  const CrmComercialScreen({super.key});

  @override
  ConsumerState<CrmComercialScreen> createState() =>
      _CrmComercialScreenState();
}

class _CrmComercialScreenState extends ConsumerState<CrmComercialScreen> {
  // Phase 1 controllers
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _nextActionCtrl = TextEditingController();
  final TextEditingController _activityTypeCtrl =
      TextEditingController(text: 'SEGUIMIENTO');
  final TextEditingController _activityDescriptionCtrl = TextEditingController();

  // Phase 2 controllers
  final TextEditingController _taskTitleCtrl = TextEditingController();
  final TextEditingController _taskDescCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _onlyMine = false;
  String _statusFilter = '';
  String _error = '';
  List<CrmComercialCustomer> _items = const <CrmComercialCustomer>[];
  List<CrmComercialUserRef> _users = const <CrmComercialUserRef>[];
  CrmComercialCustomer? _selected;

  // Phase 2 state
  List<CrmComercialFollowupTask> _allTasks = const <CrmComercialFollowupTask>[];
  bool _loadingTasks = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    _nextActionCtrl.dispose();
    _activityTypeCtrl.dispose();
    _activityDescriptionCtrl.dispose();
    _taskTitleCtrl.dispose();
    _taskDescCtrl.dispose();
    super.dispose();
  }

  List<CrmComercialFollowupTask> get _selectedTasks {
    final sel = _selected;
    if (sel == null) return const [];
    return _allTasks.where((t) => t.customerId == sel.id).toList();
  }

  int get _pendingTodayCount {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return _allTasks.where((t) {
      if (!t.isActive) return false;
      final d = t.dueDate;
      if (d == null) return false;
      return d.isAfter(todayStart.subtract(const Duration(milliseconds: 1))) &&
          d.isBefore(todayEnd);
    }).length;
  }

  int get _overdueCount =>
      _allTasks.where((t) => t.isOverdue).length;

  int get _upcomingCount {
    final now = DateTime.now();
    final in7Days = now.add(const Duration(days: 7));
    return _allTasks.where((t) {
      if (!t.isActive) return false;
      final d = t.dueDate;
      if (d == null) return false;
      return d.isAfter(now) && d.isBefore(in7Days);
    }).length;
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final repo = ref.read(crmComercialRepositoryProvider);
      final customers = await repo.listCustomers(
        q: _searchCtrl.text,
        status: _statusFilter,
        onlyMine: _onlyMine,
      );
      final users = await repo.listUsers();
      final allTasks = await repo.listFollowupTasks();

      CrmComercialCustomer? selected = _selected;
      if (selected != null) {
        final found = customers.items.where((e) => e.id == selected!.id);
        selected = found.isEmpty ? null : found.first;
      }
      selected ??= customers.items.isEmpty ? null : customers.items.first;

      if (selected != null) {
        selected = await repo.getCustomer(selected.id);
        _nextActionCtrl.text = selected.nextAction ?? '';
      }

      if (!mounted) return;
      setState(() {
        _items = customers.items;
        _users = users;
        _selected = selected;
        _allTasks = allTasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _reloadTasks() async {
    if (!mounted) return;
    setState(() => _loadingTasks = true);
    try {
      final tasks = await ref.read(crmComercialRepositoryProvider).listFollowupTasks();
      if (!mounted) return;
      setState(() => _allTasks = tasks);
    } finally {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  Future<void> _openCustomer(String id) async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final detail = await ref.read(crmComercialRepositoryProvider).getCustomer(id);
      if (!mounted) return;
      setState(() {
        _selected = detail;
        _nextActionCtrl.text = detail.nextAction ?? '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _saveNextAction() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(crmComercialRepositoryProvider)
          .updateCustomer(selected.id, nextAction: _nextActionCtrl.text.trim());
      await _openCustomer(selected.id);
      await _loadAll();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    final selected = _selected;
    if (selected == null || status == selected.estadoActual) return;
    setState(() => _saving = true);
    try {
      await ref.read(crmComercialRepositoryProvider).changeStatus(selected.id, status);
      await _openCustomer(selected.id);
      await _loadAll();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addNote() async {
    final selected = _selected;
    final note = _noteCtrl.text.trim();
    if (selected == null || note.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(crmComercialRepositoryProvider).addNote(selected.id, note);
      _noteCtrl.clear();
      await _openCustomer(selected.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assignResponsible(String? userId) async {
    final selected = _selected;
    if (selected == null || userId == null || userId.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(crmComercialRepositoryProvider)
          .updateCustomer(selected.id, responsableUserId: userId);
      await _openCustomer(selected.id);
      await _loadAll();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addActivity() async {
    final selected = _selected;
    final type = _activityTypeCtrl.text.trim();
    final description = _activityDescriptionCtrl.text.trim();
    if (selected == null || type.isEmpty || description.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(crmComercialRepositoryProvider).addActivity(
            selected.id,
            type: type,
            description: description,
          );
      _activityDescriptionCtrl.clear();
      await _openCustomer(selected.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Phase 2 actions

  Future<void> _completeTask(String taskId) async {
    setState(() => _saving = true);
    try {
      await ref.read(crmComercialRepositoryProvider).completeFollowupTask(taskId);
      await _reloadTasks();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelTask(String taskId) async {
    setState(() => _saving = true);
    try {
      await ref.read(crmComercialRepositoryProvider).cancelFollowupTask(taskId);
      await _reloadTasks();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCreateTaskDialog(BuildContext context) async {
    final selected = _selected;
    if (selected == null) return;

    _taskTitleCtrl.clear();
    _taskDescCtrl.clear();
    DateTime? dueDate;
    String priority = 'NORMAL';
    String? assignedUserId;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Nueva tarea de seguimiento'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _taskTitleCtrl,
                    decoration: const InputDecoration(labelText: 'Titulo *'),
                    maxLength: 200,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _taskDescCtrl,
                    decoration: const InputDecoration(labelText: 'Descripcion'),
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 2000,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dueDate == null
                              ? 'Sin fecha'
                              : DateFormat('dd/MM/yyyy').format(dueDate!),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(const Duration(days: 1)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Fecha'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('priority-$priority'),
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'Prioridad'),
                    items: _taskPriorities
                        .map((p) => DropdownMenuItem<String>(
                              value: p,
                              child: Text(p),
                            ))
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => priority = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('assigned-${assignedUserId ?? ''}'),
                    initialValue: assignedUserId,
                    decoration: const InputDecoration(labelText: 'Responsable'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Sin asignar'),
                      ),
                      ..._users.map((u) => DropdownMenuItem<String>(
                            value: u.id,
                            child: Text(u.nombreCompleto),
                          )),
                    ],
                    onChanged: (v) => setDialogState(() => assignedUserId = v),
                  ),
                  if (dialogError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dialogError!,
                        style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                            fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  final title = _taskTitleCtrl.text.trim();
                  if (title.length < 2) {
                    setDialogState(
                        () => dialogError = 'El titulo debe tener al menos 2 caracteres');
                    return;
                  }
                  setDialogState(() => dialogError = null);
                  Navigator.of(ctx).pop();
                  setState(() => _saving = true);
                  try {
                    await ref.read(crmComercialRepositoryProvider).createFollowupTask(
                          selected.id,
                          title: title,
                          description: _taskDescCtrl.text.trim().isEmpty
                              ? null
                              : _taskDescCtrl.text.trim(),
                          dueDate: dueDate,
                          priority: priority,
                          assignedUserId: assignedUserId,
                        );
                    await _reloadTasks();
                  } catch (error) {
                    if (mounted) setState(() => _error = error.toString());
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
                child: const Text('Crear tarea'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  Color _taskStatusColor(CrmComercialFollowupTask task) {
    if (task.isCompleted) return Colors.green;
    if (task.isCancelled) return Colors.grey;
    if (task.isOverdue) return Colors.red;
    return Colors.orange;
  }

  String _taskStatusLabel(CrmComercialFollowupTask task) {
    if (task.isCompleted) return 'Completada';
    if (task.isCancelled) return 'Cancelada';
    if (task.isOverdue) return 'Vencida';
    return 'Pendiente';
  }

  Widget _buildTaskTile(CrmComercialFollowupTask task, BuildContext context) {
    final color = _taskStatusColor(task);
    final priorityColors = <String, Color>{
      'URGENTE': Colors.red.shade700,
      'ALTA': Colors.orange.shade700,
      'NORMAL': Colors.blue.shade700,
      'BAJA': Colors.grey.shade600,
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withAlpha(100)),
                  ),
                  child: Text(
                    _taskStatusLabel(task),
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (priorityColors[task.priority] ?? Colors.grey)
                        .withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    task.priority,
                    style: TextStyle(
                      fontSize: 10,
                      color: priorityColors[task.priority] ?? Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            if (task.description != null) ...[
              const SizedBox(height: 4),
              Text(task.description!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (task.dueDate != null)
                  Text(
                    'Vence: ${DateFormat('dd/MM/yyyy').format(task.dueDate!)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: task.isOverdue ? Colors.red : Colors.grey.shade600,
                    ),
                  ),
                if (task.assignedTo != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    task.assignedTo!.nombreCompleto,
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
                const Spacer(),
                if (task.isActive) ...[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _completeTask(task.id),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Completar'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _cancelTask(task.id),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      appBar: const CustomAppBar(title: 'CRM Comercial'),
      drawer: const AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Summary bar
                  if (_allTasks.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            const Text(
                              'Tareas: ',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            _SummaryChip(
                              label: 'Hoy',
                              count: _pendingTodayCount,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            _SummaryChip(
                              label: 'Vencidas',
                              count: _overdueCount,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 8),
                            _SummaryChip(
                              label: 'Proximas 7d',
                              count: _upcomingCount,
                              color: Colors.orange,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Buscar cliente',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: (_) => _loadAll(),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('status-filter-$_statusFilter'),
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Estado',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Todos'),
                            ),
                            ..._crmStatuses.map(
                              (status) => DropdownMenuItem<String>(
                                value: status,
                                child: Text(_statusLabel(status)),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _statusFilter = (value ?? '').trim();
                            });
                            _loadAll();
                          },
                        ),
                      ),
                      FilterChip(
                        selected: _onlyMine,
                        label: const Text('Solo asignados a mi'),
                        onSelected: (value) {
                          setState(() => _onlyMine = value);
                          _loadAll();
                        },
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _loadAll,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar'),
                      ),
                    ],
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final mobileLayout = constraints.maxWidth < 1100;
                        final listPanel = Card(
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final active = selected?.id == item.id;
                              final taskCount = _allTasks
                                  .where((t) =>
                                      t.customerId == item.id && t.isActive)
                                  .length;
                              return ListTile(
                                selected: active,
                                title: Text(item.nombre),
                                subtitle: Text(
                                  '${item.telefono} - ${_statusLabel(item.estadoActual)}',
                                ),
                                trailing: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      item.responsable?.nombreCompleto ??
                                          'Sin responsable',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    if (taskCount > 0)
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withAlpha(40),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$taskCount tarea${taskCount == 1 ? '' : 's'}',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.deepOrange),
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: _saving ? null : () => _openCustomer(item.id),
                              );
                            },
                          ),
                        );

                        final detailPanel = selected == null
                            ? const Card(
                                child: Center(
                                  child: Text('Selecciona un cliente CRM comercial'),
                                ),
                              )
                            : Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selected.nombre,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(selected.telefono),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _crmStatuses
                                              .map(
                                                (status) => ChoiceChip(
                                                  label: Text(
                                                    _statusLabel(status),
                                                  ),
                                                  selected:
                                                      selected.estadoActual ==
                                                      status,
                                                  onSelected: _saving
                                                      ? null
                                                      : (_) =>
                                                          _changeStatus(status),
                                                ),
                                              )
                                              .toList(growable: false),
                                        ),
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<String>(
                                          key: ValueKey(
                                            'responsable-${selected.id}-${selected.responsable?.id ?? ''}',
                                          ),
                                          initialValue: selected.responsable?.id,
                                          decoration: const InputDecoration(
                                            labelText: 'Responsable',
                                          ),
                                          items: _users
                                              .map(
                                                (user) => DropdownMenuItem<String>(
                                                  value: user.id,
                                                  child: Text(user.nombreCompleto),
                                                ),
                                              )
                                              .toList(growable: false),
                                          onChanged:
                                              _saving ? null : _assignResponsible,
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _nextActionCtrl,
                                          minLines: 1,
                                          maxLines: 2,
                                          decoration: const InputDecoration(
                                            labelText: 'Proxima accion',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FilledButton(
                                            onPressed:
                                                _saving ? null : _saveNextAction,
                                            child: const Text('Guardar accion'),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Notas',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _noteCtrl,
                                          minLines: 2,
                                          maxLines: 3,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Agregar nota de seguimiento',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FilledButton.icon(
                                            onPressed: _saving ? null : _addNote,
                                            icon: const Icon(Icons.note_add_outlined),
                                            label: const Text('Agregar nota'),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...selected.notes.map(
                                          (note) => ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(note.note),
                                            subtitle: Text(
                                              '${note.author?.nombreCompleto ?? 'Sistema'} - ${note.createdAt == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(note.createdAt!)}',
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 20),
                                        Text(
                                          'Actividades',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _activityTypeCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Tipo de actividad',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _activityDescriptionCtrl,
                                          minLines: 2,
                                          maxLines: 3,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'Descripcion de actividad o seguimiento',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FilledButton.icon(
                                            onPressed:
                                                _saving ? null : _addActivity,
                                            icon: const Icon(Icons.task_alt),
                                            label: const Text('Agregar actividad'),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        ...selected.activities.map(
                                          (activity) => ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              '${activity.activityType}: ${activity.description}',
                                            ),
                                            subtitle: Text(
                                              '${activity.createdBy?.nombreCompleto ?? 'Sistema'} - ${activity.createdAt == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(activity.createdAt!)}',
                                            ),
                                          ),
                                        ),
                                        const Divider(height: 20),

                                        // Phase 2: Seguimiento
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Seguimiento',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            TextButton.icon(
                                              onPressed: (_saving || _loadingTasks)
                                                  ? null
                                                  : () => _openCreateTaskDialog(
                                                      context),
                                              icon: const Icon(Icons.add_task,
                                                  size: 18),
                                              label: const Text('Nueva tarea'),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        if (_loadingTasks)
                                          const Center(
                                            child: Padding(
                                              padding: EdgeInsets.all(8),
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          )
                                        else if (_selectedTasks.isEmpty)
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                                vertical: 8),
                                            child: Text(
                                              'Sin tareas de seguimiento',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 13),
                                            ),
                                          )
                                        else
                                          ..._selectedTasks.map(
                                            (task) =>
                                                _buildTaskTile(task, context),
                                          ),

                                        const Divider(height: 20),
                                        Text(
                                          'Historial de estados',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        ...selected.statusHistory.map(
                                          (entry) => ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(
                                              '${_statusLabel(entry.estadoAnterior ?? 'NUEVO')} -> ${_statusLabel(entry.estadoNuevo)}',
                                            ),
                                            subtitle: Text(
                                              '${entry.changedBy?.nombreCompleto ?? 'Sistema'} - ${entry.createdAt == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(entry.createdAt!)}',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );

                        if (mobileLayout) {
                          return Column(
                            children: [
                              Expanded(flex: 3, child: listPanel),
                              const SizedBox(height: 12),
                              Expanded(flex: 4, child: detailPanel),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(flex: 4, child: listPanel),
                            const SizedBox(width: 12),
                            Expanded(flex: 5, child: detailPanel),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(count > 0 ? 30 : 15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(count > 0 ? 120 : 50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: count > 0 ? color : Colors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: count > 0 ? color : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}