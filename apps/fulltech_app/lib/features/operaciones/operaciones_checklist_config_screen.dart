import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import 'data/operations_repository.dart';
import 'operations_models.dart';
import 'presentation/operations_back_button.dart';

class OperacionesChecklistConfigScreen extends ConsumerStatefulWidget {
  const OperacionesChecklistConfigScreen({super.key});

  @override
  ConsumerState<OperacionesChecklistConfigScreen> createState() =>
      _OperacionesChecklistConfigScreenState();
}

class _OperacionesChecklistConfigScreenState
    extends ConsumerState<OperacionesChecklistConfigScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<ServiceChecklistCategoryModel> _categories = const [];
  List<ServiceChecklistPhaseModel> _phases = const [];
  List<ServiceChecklistTemplateModel> _templates = const [];

  String? _selectedCategoryId;
  String? _selectedPhaseId;

  bool get _canManage {
    final role = ref.read(authStateProvider).user?.appRole ?? AppRole.unknown;
    return role == AppRole.admin ||
        role == AppRole.asistente ||
        role == AppRole.vendedor;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadAll);
  }

  Future<void> _loadAll({bool preserveSelection = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(operationsRepositoryProvider);
      final categories = await repo.listChecklistCategories();
      final phases = await repo.listChecklistPhases();

      String? nextCategoryId = preserveSelection ? _selectedCategoryId : null;
      String? nextPhaseId = preserveSelection ? _selectedPhaseId : null;

      if (categories.isNotEmpty) {
        final hasSelected = categories.any((item) => item.id == nextCategoryId);
        nextCategoryId = hasSelected ? nextCategoryId : categories.first.id;
      } else {
        nextCategoryId = null;
      }

      if (phases.isNotEmpty) {
        final hasSelected = phases.any((item) => item.id == nextPhaseId);
        nextPhaseId = hasSelected ? nextPhaseId : phases.first.id;
      } else {
        nextPhaseId = null;
      }

      final templates = await repo.listChecklistTemplates(
        categoryId: nextCategoryId,
        phaseId: nextPhaseId,
      );

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _phases = phases;
        _templates = templates;
        _selectedCategoryId = nextCategoryId;
        _selectedPhaseId = nextPhaseId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'No se pudo cargar la configuración de checklist';
      });
    }
  }

  Future<void> _reloadTemplates() async {
    if (_selectedCategoryId == null || _selectedPhaseId == null) {
      setState(() => _templates = const []);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final templates = await ref.read(operationsRepositoryProvider).listChecklistTemplates(
        categoryId: _selectedCategoryId,
        phaseId: _selectedPhaseId,
      );
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'No se pudieron cargar los checklists';
      });
    }
  }

  Future<void> _withSaving(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _createCategory() async {
    final payload = await _showNameCodeDialog(
      title: 'Nueva categoría',
      nameLabel: 'Nombre de categoría',
      nameHint: 'Ej. Cámaras',
      codeHint: 'Ej. camaras',
    );
    if (payload == null) return;

    await _withSaving(() async {
      final created = await ref.read(operationsRepositoryProvider).createChecklistCategory(
            name: payload.name,
            code: payload.code,
          );
      await _loadAll(preserveSelection: false);
      if (!mounted) return;
      setState(() => _selectedCategoryId = created.id);
      await _reloadTemplates();
      _showMessage('Categoría creada');
    });
  }

  Future<void> _createPhase() async {
    final payload = await _showNameCodeDialog(
      title: 'Nueva fase',
      nameLabel: 'Nombre de fase',
      nameHint: 'Ej. Herramientas',
      codeHint: 'Ej. herramientas',
      askOrder: true,
    );
    if (payload == null) return;

    await _withSaving(() async {
      final created = await ref.read(operationsRepositoryProvider).createChecklistPhase(
            name: payload.name,
            code: payload.code,
            orderIndex: payload.orderIndex,
          );
      await _loadAll(preserveSelection: false);
      if (!mounted) return;
      setState(() => _selectedPhaseId = created.id);
      await _reloadTemplates();
      _showMessage('Fase creada');
    });
  }

  Future<void> _createChecklist() async {
    final categoryId = _selectedCategoryId;
    final phaseId = _selectedPhaseId;
    if (categoryId == null || phaseId == null) {
      _showMessage('Primero crea y selecciona una categoría y una fase');
      return;
    }

    final title = await _showSingleFieldDialog(
      title: 'Crear checklist',
      label: 'Nombre del checklist',
      hint: 'Ej. Preparación del kit',
    );
    if (title == null) return;

    await _withSaving(() async {
      await ref.read(operationsRepositoryProvider).createChecklistTemplate(
            categoryId: categoryId,
            phaseId: phaseId,
            title: title,
          );
      await _reloadTemplates();
      _showMessage('Checklist creado');
    });
  }

  Future<void> _createItem(ServiceChecklistTemplateModel template) async {
    final payload = await _showCreateItemDialog(template.title);
    if (payload == null) return;

    await _withSaving(() async {
      await ref.read(operationsRepositoryProvider).createChecklistItem(
            templateId: template.id,
            label: payload.label,
            isRequired: payload.isRequired,
            orderIndex: template.items.length,
          );
      await _reloadTemplates();
      _showMessage('Ítem agregado');
    });
  }

  Future<_NameCodePayload?> _showNameCodeDialog({
    required String title,
    required String nameLabel,
    required String nameHint,
    required String codeHint,
    bool askOrder = false,
  }) async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final orderCtrl = TextEditingController(text: '0');

    final result = await showModalBottomSheet<_NameCodePayload>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ChecklistFormSheet(
          title: title,
          child: Column(
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: nameLabel,
                  hintText: nameHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                decoration: InputDecoration(
                  labelText: 'Código',
                  hintText: codeHint,
                ),
              ),
              if (askOrder) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: orderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Orden visual',
                    hintText: '0',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(
                      context,
                      _NameCodePayload(
                        name: name,
                        code: codeCtrl.text.trim(),
                        orderIndex: int.tryParse(orderCtrl.text.trim()) ?? 0,
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
              ),
            ],
          ),
        );
      },
    );

    nameCtrl.dispose();
    codeCtrl.dispose();
    orderCtrl.dispose();
    return result;
  }

  Future<String?> _showSingleFieldDialog({
    required String title,
    required String label,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ChecklistFormSheet(
          title: title,
          child: Column(
            children: [
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: label, hintText: hint),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final value = ctrl.text.trim();
                    if (value.isEmpty) return;
                    Navigator.pop(context, value);
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Crear checklist'),
                ),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  Future<_CreateItemPayload?> _showCreateItemDialog(String checklistTitle) async {
    final labelCtrl = TextEditingController();
    var isRequired = true;

    final result = await showModalBottomSheet<_CreateItemPayload>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _ChecklistFormSheet(
              title: 'Agregar ítem',
              subtitle: checklistTitle,
              child: Column(
                children: [
                  TextField(
                    controller: labelCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Ítem',
                      hintText: 'Ej. Taladro cargado',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ítem obligatorio'),
                    subtitle: const Text('Cuenta para el progreso principal'),
                    value: isRequired,
                    onChanged: (value) {
                      setModalState(() => isRequired = value);
                    },
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        final label = labelCtrl.text.trim();
                        if (label.isEmpty) return;
                        Navigator.pop(
                          context,
                          _CreateItemPayload(
                            label: label,
                            isRequired: isRequired,
                          ),
                        );
                      },
                      icon: const Icon(Icons.playlist_add_outlined),
                      label: const Text('Agregar ítem'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    labelCtrl.dispose();
    return result;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedCategory = _categories.cast<ServiceChecklistCategoryModel?>().firstWhere(
          (item) => item?.id == _selectedCategoryId,
          orElse: () => null,
        );

    return Scaffold(
      appBar: AppBar(
        leading: const OperationsBackButton(fallbackRoute: Routes.operaciones),
        title: const Text('Configuración de Checklist'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : _createChecklist,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_rounded),
              label: const Text('Crear checklist'),
            )
          : null,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primary.withValues(alpha: 0.07),
              cs.surface,
              cs.surface,
            ],
          ),
        ),
        child: _canManage
            ? RefreshIndicator(
                onRefresh: _loadAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    _AdminHeroCard(
                      categoriesCount: _categories.length,
                      phasesCount: _phases.length,
                      templatesCount: _templates.length,
                      onCreateCategory: _saving ? null : _createCategory,
                      onCreatePhase: _saving ? null : _createPhase,
                    ),
                    const SizedBox(height: 16),
                    _FilterCard(
                      categories: _categories,
                      phases: _phases,
                      selectedCategoryId: _selectedCategoryId,
                      selectedPhaseId: _selectedPhaseId,
                      onCategoryChanged: (value) async {
                        setState(() => _selectedCategoryId = value);
                        await _reloadTemplates();
                      },
                      onPhaseChanged: (value) async {
                        setState(() => _selectedPhaseId = value);
                        await _reloadTemplates();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      _ErrorCard(message: _error!, onRetry: _loadAll),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!_loading && _error == null && _templates.isEmpty)
                      _EmptyChecklistCard(
                        categoryLabel: selectedCategory?.name,
                        onCreateChecklist: _saving ? null : _createChecklist,
                      ),
                    if (!_loading && _templates.isNotEmpty)
                      ..._templates.map(
                        (template) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ChecklistTemplateAdminCard(
                            template: template,
                            onAddItem: _saving ? null : () => _createItem(template),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : const _ChecklistConfigLocked(),
      ),
    );
  }
}

class _ChecklistConfigLocked extends StatelessWidget {
  const _ChecklistConfigLocked();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 42, color: cs.primary),
              const SizedBox(height: 12),
              Text(
                'Solo perfiles administrativos pueden gestionar checklists.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminHeroCard extends StatelessWidget {
  final int categoriesCount;
  final int phasesCount;
  final int templatesCount;
  final VoidCallback? onCreateCategory;
  final VoidCallback? onCreatePhase;

  const _AdminHeroCard({
    required this.categoriesCount,
    required this.phasesCount,
    required this.templatesCount,
    required this.onCreateCategory,
    required this.onCreatePhase,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B132B), Color(0xFF1C4ED8), Color(0xFF60A5FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330B132B),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configuración de Checklist',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Administra categorías, fases, plantillas e ítems desde una sola vista. El técnico recibe solo lo que necesita en cada paso.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatPill(label: 'Categorías', value: '$categoriesCount'),
              _StatPill(label: 'Fases', value: '$phasesCount'),
              _StatPill(label: 'Checklists', value: '$templatesCount'),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: onCreateCategory,
                icon: const Icon(Icons.category_outlined),
                label: const Text('Nueva categoría'),
              ),
              FilledButton.tonalIcon(
                onPressed: onCreatePhase,
                icon: const Icon(Icons.layers_outlined),
                label: const Text('Nueva fase'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  final List<ServiceChecklistCategoryModel> categories;
  final List<ServiceChecklistPhaseModel> phases;
  final String? selectedCategoryId;
  final String? selectedPhaseId;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onPhaseChanged;

  const _FilterCard({
    required this.categories,
    required this.phases,
    required this.selectedCategoryId,
    required this.selectedPhaseId,
    required this.onCategoryChanged,
    required this.onPhaseChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filtros de edición',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: selectedCategoryId,
            items: categories
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.id,
                    child: Text(item.name),
                  ),
                )
                .toList(growable: false),
            onChanged: onCategoryChanged,
            decoration: const InputDecoration(
              labelText: 'Categoría',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: phases
                .map(
                  (phase) => ChoiceChip(
                    label: Text(phase.name),
                    selected: phase.id == selectedPhaseId,
                    onSelected: (_) => onPhaseChanged(phase.id),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ChecklistTemplateAdminCard extends StatelessWidget {
  final ServiceChecklistTemplateModel template;
  final VoidCallback? onAddItem;

  const _ChecklistTemplateAdminCard({
    required this.template,
    required this.onAddItem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaChip(label: template.category.name),
                        _MetaChip(label: template.phase.name),
                        _MetaChip(label: '${template.items.length} ítems'),
                      ],
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onAddItem,
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Agregar item'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (template.items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                'Este checklist aún no tiene ítems. Agrega el primero para empezar a guiar al técnico.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (template.items.isNotEmpty)
            ...template.items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: index == template.items.length - 1 ? 0 : 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: item.isRequired
                        ? cs.primary.withValues(alpha: 0.06)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: item.isRequired
                          ? cs.primary.withValues(alpha: 0.18)
                          : cs.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: item.isRequired
                              ? Colors.green.withValues(alpha: 0.14)
                              : cs.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item.isRequired
                              ? Icons.checklist_rtl_outlined
                              : Icons.label_important_outline_rounded,
                          color: item.isRequired ? Colors.green : cs.onSurfaceVariant,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _MetaChip(label: item.isRequired ? 'Obligatorio' : 'Opcional'),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;

  const _MetaChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyChecklistCard extends StatelessWidget {
  final String? categoryLabel;
  final VoidCallback? onCreateChecklist;

  const _EmptyChecklistCard({
    required this.categoryLabel,
    required this.onCreateChecklist,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Column(
        children: [
          Icon(Icons.playlist_remove_outlined, size: 42, color: cs.primary),
          const SizedBox(height: 12),
          Text(
            'No hay checklists para ${categoryLabel ?? 'esta selección'}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea un checklist para empezar a controlar herramientas, productos, instalación o cierre.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreateChecklist,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Crear checklist'),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _ChecklistFormSheet extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _ChecklistFormSheet({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _NameCodePayload {
  final String name;
  final String code;
  final int orderIndex;

  const _NameCodePayload({
    required this.name,
    required this.code,
    required this.orderIndex,
  });
}

class _CreateItemPayload {
  final String label;
  final bool isRequired;

  const _CreateItemPayload({required this.label, required this.isRequired});
}
