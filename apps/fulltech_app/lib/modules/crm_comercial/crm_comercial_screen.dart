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

class CrmComercialScreen extends ConsumerStatefulWidget {
  const CrmComercialScreen({super.key});

  @override
  ConsumerState<CrmComercialScreen> createState() =>
      _CrmComercialScreenState();
}

class _CrmComercialScreenState extends ConsumerState<CrmComercialScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _nextActionCtrl = TextEditingController();
  final TextEditingController _activityTypeCtrl =
      TextEditingController(text: 'SEGUIMIENTO');
  final TextEditingController _activityDescriptionCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _onlyMine = false;
  String _statusFilter = '';
  String _error = '';
  List<CrmComercialCustomer> _items = const <CrmComercialCustomer>[];
  List<CrmComercialUserRef> _users = const <CrmComercialUserRef>[];
  CrmComercialCustomer? _selected;

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
    super.dispose();
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

  String _statusLabel(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
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
                              return ListTile(
                                selected: active,
                                title: Text(item.nombre),
                                subtitle: Text(
                                  '${item.telefono} - ${_statusLabel(item.estadoActual)}',
                                ),
                                trailing: Text(
                                  item.responsable?.nombreCompleto ??
                                      'Sin responsable',
                                  style: Theme.of(context).textTheme.bodySmall,
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
                                            icon:
                                                const Icon(Icons.note_add_outlined),
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
