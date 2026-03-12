import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import 'company_manual_models.dart';
import 'company_manual_repository.dart';

class ManualInternoScreen extends ConsumerStatefulWidget {
  const ManualInternoScreen({super.key});

  @override
  ConsumerState<ManualInternoScreen> createState() =>
      _ManualInternoScreenState();
}

class _ManualInternoScreenState extends ConsumerState<ManualInternoScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<CompanyManualEntry> _entries = const [];
  CompanyManualEntryKind? _kindFilter;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final user = ref.read(authStateProvider).user;
    final canManage =
        user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(companyManualRepositoryProvider);
      final items = await repo.listEntries(
        kind: _kindFilter,
        includeHidden: canManage,
      );

      DateTime? latest;
      for (final item in items) {
        final updatedAt = item.updatedAt ?? item.createdAt;
        if (updatedAt == null) continue;
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }
      if (latest != null) {
        await repo.markSeen(latest);
        ref.invalidate(companyManualSummaryProvider);
      }

      if (!mounted) return;
      setState(() {
        _entries = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<CompanyManualEntry> get _visibleEntries {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where((item) {
          return item.title.toLowerCase().contains(query) ||
              (item.summary ?? '').toLowerCase().contains(query) ||
              item.content.toLowerCase().contains(query) ||
              (item.moduleKey ?? '').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _openEditor({CompanyManualEntry? entry}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CompanyManualEntryDialog(entry: entry),
    );
    if (saved == true) {
      await _loadEntries();
    }
  }

  Future<void> _deleteEntry(CompanyManualEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar entrada'),
        content: Text('¿Deseas eliminar "${entry.title}"?'),
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
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(companyManualRepositoryProvider).deleteEntry(entry.id);
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canManage =
        user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);
    final entries = _visibleEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Interno'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _loadEntries,
            icon: const Icon(Icons.refresh),
          ),
          if (canManage)
            IconButton(
              tooltip: 'Nueva entrada',
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar reglas, políticas, guías o módulos...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Todo'),
                    selected: _kindFilter == null,
                    onSelected: (_) {
                      setState(() => _kindFilter = null);
                      _loadEntries();
                    },
                  ),
                ),
                for (final kind in CompanyManualEntryKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(kind.label),
                      selected: _kindFilter == kind,
                      onSelected: (_) {
                        setState(() => _kindFilter = kind);
                        _loadEntries();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : entries.isEmpty
                ? const Center(child: Text('No hay entradas para mostrar'))
                : RefreshIndicator(
                    onRefresh: _loadEntries,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final roles = entry.targetRoles
                            .map((role) => role.label)
                            .join(', ');
                        final updatedAt = entry.updatedAt ?? entry.createdAt;

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              Chip(
                                                label: Text(entry.kind.label),
                                              ),
                                              Chip(
                                                label: Text(
                                                  entry.audience.label,
                                                ),
                                              ),
                                              if (entry.moduleKey != null &&
                                                  entry.moduleKey!.isNotEmpty)
                                                Chip(
                                                  label: Text(
                                                    'Módulo: ${entry.moduleKey}',
                                                  ),
                                                ),
                                              if (roles.isNotEmpty)
                                                Chip(
                                                  label: Text('Roles: $roles'),
                                                ),
                                              if (!entry.published)
                                                const Chip(
                                                  label: Text('Oculto'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (canManage)
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _openEditor(entry: entry);
                                          } else if (value == 'delete') {
                                            _deleteEntry(entry);
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Editar'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Eliminar'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                if (entry.summary != null &&
                                    entry.summary!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.summary!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                SelectableText(entry.content),
                                if (updatedAt != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Actualizado: ${updatedAt.day.toString().padLeft(2, '0')}/${updatedAt.month.toString().padLeft(2, '0')}/${updatedAt.year} ${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva entrada'),
            )
          : null,
    );
  }
}

class _CompanyManualEntryDialog extends ConsumerStatefulWidget {
  const _CompanyManualEntryDialog({this.entry});

  final CompanyManualEntry? entry;

  @override
  ConsumerState<_CompanyManualEntryDialog> createState() =>
      _CompanyManualEntryDialogState();
}

class _CompanyManualEntryDialogState
    extends ConsumerState<_CompanyManualEntryDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _moduleCtrl;
  late final TextEditingController _sortCtrl;

  late CompanyManualEntryKind _kind;
  late CompanyManualAudience _audience;
  late bool _published;
  late Set<AppRole> _targetRoles;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?.title ?? '');
    _summaryCtrl = TextEditingController(text: widget.entry?.summary ?? '');
    _contentCtrl = TextEditingController(text: widget.entry?.content ?? '');
    _moduleCtrl = TextEditingController(text: widget.entry?.moduleKey ?? '');
    _sortCtrl = TextEditingController(
      text: (widget.entry?.sortOrder ?? 0).toString(),
    );
    _kind = widget.entry?.kind ?? CompanyManualEntryKind.generalRule;
    _audience = widget.entry?.audience ?? CompanyManualAudience.general;
    _published = widget.entry?.published ?? true;
    _targetRoles = {...?widget.entry?.targetRoles};
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _contentCtrl.dispose();
    _moduleCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final sortOrder = int.tryParse(_sortCtrl.text.trim()) ?? 0;
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = 'Título y contenido son obligatorios');
      return;
    }
    if (_audience == CompanyManualAudience.roleSpecific &&
        _targetRoles.isEmpty) {
      setState(
        () => _error = 'Selecciona al menos un rol para una entrada por rol',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final entry = CompanyManualEntry(
      id: widget.entry?.id ?? '',
      ownerId: widget.entry?.ownerId ?? '',
      title: title,
      summary: _summaryCtrl.text.trim().isEmpty
          ? null
          : _summaryCtrl.text.trim(),
      content: content,
      kind: _kind,
      audience: _audience,
      targetRoles: _targetRoles.toList()
        ..sort((a, b) => a.label.compareTo(b.label)),
      moduleKey: _moduleCtrl.text.trim().isEmpty
          ? null
          : _moduleCtrl.text.trim(),
      published: _published,
      sortOrder: sortOrder,
      createdByUserId: widget.entry?.createdByUserId ?? '',
      updatedByUserId: widget.entry?.updatedByUserId,
      createdAt: widget.entry?.createdAt,
      updatedAt: widget.entry?.updatedAt,
    );

    try {
      final repo = ref.read(companyManualRepositoryProvider);
      if (widget.entry == null) {
        await repo.createEntry(entry);
      } else {
        await repo.updateEntry(entry);
      }
      ref.invalidate(companyManualSummaryProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry == null ? 'Nueva entrada' : 'Editar entrada'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _summaryCtrl,
              decoration: const InputDecoration(
                labelText: 'Resumen breve (opcional)',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CompanyManualEntryKind>(
              initialValue: _kind,
              items: CompanyManualEntryKind.values
                  .map(
                    (kind) =>
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _kind = value);
                    },
              decoration: const InputDecoration(labelText: 'Tipo de entrada'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CompanyManualAudience>(
              initialValue: _audience,
              items: CompanyManualAudience.values
                  .map(
                    (audience) => DropdownMenuItem(
                      value: audience,
                      child: Text(audience.label),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _audience = value;
                        if (_audience == CompanyManualAudience.general) {
                          _targetRoles.clear();
                        }
                      });
                    },
              decoration: const InputDecoration(labelText: 'Alcance'),
            ),
            if (_audience == CompanyManualAudience.roleSpecific) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in [
                    AppRole.asistente,
                    AppRole.vendedor,
                    AppRole.marketing,
                    AppRole.tecnico,
                    AppRole.admin,
                  ])
                    FilterChip(
                      label: Text(role.label),
                      selected: _targetRoles.contains(role),
                      onSelected: _saving
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _targetRoles.add(role);
                                } else {
                                  _targetRoles.remove(role);
                                }
                              });
                            },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _moduleCtrl,
              decoration: const InputDecoration(
                labelText: 'Módulo relacionado (opcional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sortCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Orden'),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _published,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _published = value),
              title: const Text('Visible para usuarios'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contentCtrl,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Contenido',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
