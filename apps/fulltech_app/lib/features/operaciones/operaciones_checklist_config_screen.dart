import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import 'application/operations_metadata_providers.dart';
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
  static const List<ServiceChecklistSectionType> _sectionTypes = [
    ServiceChecklistSectionType.herramientas,
    ServiceChecklistSectionType.productos,
    ServiceChecklistSectionType.instalacion,
  ];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<ServiceChecklistTemplateModel> _templates = const [];

  String? _selectedCategoryId;
  String? _selectedPhaseId;
  String? _loadedCategoryId;
  String? _loadedPhaseId;

  bool get _canManage {
    final role = ref.read(authStateProvider).user?.appRole ?? AppRole.unknown;
    return role == AppRole.admin ||
        role == AppRole.asistente ||
        role == AppRole.vendedor;
  }

  @override
  void initState() {
    super.initState();
  }

  String? _defaultCategoryId(List<ServiceChecklistCategoryModel> categories) {
    for (final item in categories) {
      if (item.code.trim().toLowerCase() == 'cameras') return item.id;
    }
    return categories.isEmpty ? null : categories.first.id;
  }

  void _syncSelection({
    required List<ServiceChecklistCategoryModel> categories,
    required List<ServiceChecklistPhaseModel> phases,
  }) {
    final nextCategoryId = categories.any((item) => item.id == _selectedCategoryId)
        ? _selectedCategoryId
        : _defaultCategoryId(categories);
    final nextPhaseId = phases.any((item) => item.id == _selectedPhaseId)
        ? _selectedPhaseId
        : (phases.isEmpty ? null : phases.first.id);

    final needsSelectionUpdate =
        nextCategoryId != _selectedCategoryId || nextPhaseId != _selectedPhaseId;
    final needsTemplateReload =
        nextCategoryId != null &&
        nextPhaseId != null &&
        (_loadedCategoryId != nextCategoryId || _loadedPhaseId != nextPhaseId);

    if (!needsSelectionUpdate && !needsTemplateReload) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (needsSelectionUpdate) {
        setState(() {
          _selectedCategoryId = nextCategoryId;
          _selectedPhaseId = nextPhaseId;
        });
      }
      if (needsTemplateReload) {
        await _reloadTemplates(
          categoryId: nextCategoryId,
          phaseId: nextPhaseId,
        );
      }
    });
  }

  Future<void> _refreshMetadataAndTemplates() async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(servicePhasesProvider);
    await _reloadTemplates(forceClear: true);
  }

  Future<void> _reloadTemplates({
    String? categoryId,
    String? phaseId,
    bool forceClear = false,
  }) async {
    final effectiveCategoryId = categoryId ?? _selectedCategoryId;
    final effectivePhaseId = phaseId ?? _selectedPhaseId;

    if (effectiveCategoryId == null || effectivePhaseId == null) {
      setState(() {
        _templates = const [];
        _loading = false;
        _loadedCategoryId = null;
        _loadedPhaseId = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      if (forceClear) _templates = const [];
    });

    try {
      final templates = await ref.read(operationsRepositoryProvider).listChecklistTemplates(
        categoryId: effectiveCategoryId,
        phaseId: effectivePhaseId,
      );
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
        _loadedCategoryId = effectiveCategoryId;
        _loadedPhaseId = effectivePhaseId;
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

  Future<void> _createChecklist(ServiceChecklistSectionType type, List<_CreateItemPayload> items) async {
    final categoryId = _selectedCategoryId;
    final phaseId = _selectedPhaseId;
    if (categoryId == null || phaseId == null) {
      _showMessage('Primero selecciona una categoría y una fase');
      return;
    }

    await _withSaving(() async {
      await ref.read(operationsRepositoryProvider).createChecklistTemplate(
            categoryId: categoryId,
            phaseId: phaseId,
            type: type,
            title: serviceChecklistSectionTypeLabel(type),
          );
      final template = await _resolveTemplateForType(type);
      if (template != null) {
        for (final item in items) {
          await ref.read(operationsRepositoryProvider).createChecklistItem(
                templateId: template.id,
                label: item.label,
                isRequired: item.isRequired,
                orderIndex: item.orderIndex,
              );
        }
      }
      await _reloadTemplates();
      _showMessage('${serviceChecklistSectionTypeLabel(type)} creada correctamente');
    });
  }

  Future<ServiceChecklistTemplateModel?> _resolveTemplateForType(
    ServiceChecklistSectionType type,
  ) async {
    final categoryId = _selectedCategoryId;
    final phaseId = _selectedPhaseId;
    if (categoryId == null || phaseId == null) return null;

    final templates = await ref.read(operationsRepositoryProvider).listChecklistTemplates(
      categoryId: categoryId,
      phaseId: phaseId,
    );
    for (final template in templates) {
      if (template.type == type) return template;
    }
    return null;
  }

  Future<void> _openCreateChecklistDialog() async {
    final payload = await _showCreateChecklistDialog();
    if (payload == null) return;
    await _createChecklist(payload.type, payload.items);
  }

  Future<void> _createItem(ServiceChecklistTemplateModel template) async {
    final payload = await _showCreateItemDialog(template.title);
    if (payload == null) return;

    await _withSaving(() async {
      await ref.read(operationsRepositoryProvider).createChecklistItem(
            templateId: template.id,
            label: payload.label,
            isRequired: payload.isRequired,
            orderIndex: payload.orderIndex,
          );
      await _reloadTemplates();
      _showMessage('Ítem agregado');
    });
  }

  ServiceChecklistTemplateModel? _templateForType(
    ServiceChecklistSectionType type,
  ) {
    for (final template in _templates) {
      if (template.type == type) return template;
    }
    return null;
  }

  Future<_CreateItemPayload?> _showCreateItemDialog(String checklistTitle) async {
    final labelCtrl = TextEditingController();
    final orderCtrl = TextEditingController(text: '0');
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
                  TextField(
                    controller: orderCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Orden visual',
                      hintText: '0',
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
                            orderIndex: int.tryParse(orderCtrl.text.trim()) ?? 0,
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
    orderCtrl.dispose();
    return result;
  }

  Future<_CreateChecklistPayload?> _showCreateChecklistDialog() async {
    var type = ServiceChecklistSectionType.herramientas;
    final labelCtrl = TextEditingController();
    final orderCtrl = TextEditingController(text: '0');
    var isRequired = true;
    final items = <_CreateItemPayload>[];

    final result = await showModalBottomSheet<_CreateChecklistPayload>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void addItem() {
              final label = labelCtrl.text.trim();
              if (label.isEmpty) return;
              setModalState(() {
                items.add(
                  _CreateItemPayload(
                    label: label,
                    isRequired: isRequired,
                    orderIndex: int.tryParse(orderCtrl.text.trim()) ?? items.length,
                  ),
                );
                labelCtrl.clear();
                orderCtrl.text = '${items.length}';
                isRequired = true;
              });
            }

            return _ChecklistFormSheet(
              title: 'Crear checklist',
              subtitle: 'Selecciona el tipo y agrega los ítems iniciales',
              child: Column(
                children: [
                  DropdownButtonFormField<ServiceChecklistSectionType>(
                    initialValue: type,
                    items: _sectionTypes
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(serviceChecklistSectionTypeLabel(item)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() => type = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      prefixIcon: Icon(Icons.widgets_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Ítem',
                      hintText: 'Ej. Taladro cargado',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: orderCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Orden visual',
                      hintText: '0',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ítem obligatorio'),
                    value: isRequired,
                    onChanged: (value) => setModalState(() => isRequired = value),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: addItem,
                      icon: const Icon(Icons.add_task_outlined),
                      label: const Text('Agregar ítem'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const _InlineHintCard(
                      text: 'Agrega al menos un ítem para crear el checklist.',
                    ),
                  if (items.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.label,
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Orden ${item.orderIndex} · ${item.isRequired ? 'Obligatorio' : 'Opcional'}',
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setModalState(() => items.removeAt(index));
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: items.isEmpty
                          ? null
                          : () {
                              Navigator.pop(
                                context,
                                _CreateChecklistPayload(type: type, items: List<_CreateItemPayload>.from(items)),
                              );
                            },
                      icon: const Icon(Icons.playlist_add_check_circle_outlined),
                      label: const Text('Crear checklist'),
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
    orderCtrl.dispose();
    return result;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesValue = ref.watch(categoriesProvider);
    final phasesValue = ref.watch(servicePhasesProvider);
    final categories = categoriesValue.maybeWhen(
      data: (items) => items,
      orElse: () => const <ServiceChecklistCategoryModel>[],
    );
    final phases = phasesValue.maybeWhen(
      data: (items) => items,
      orElse: () => const <ServiceChecklistPhaseModel>[],
    );
    _syncSelection(categories: categories, phases: phases);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectedCategory = categories.cast<ServiceChecklistCategoryModel?>().firstWhere(
          (item) => item?.id == _selectedCategoryId,
          orElse: () => null,
        );
    final selectedPhase = phases.cast<ServiceChecklistPhaseModel?>().firstWhere(
          (item) => item?.id == _selectedPhaseId,
          orElse: () => null,
        );
    final metadataLoading = categoriesValue.isLoading || phasesValue.isLoading;
    final metadataError = categoriesValue.whenOrNull(error: (error, _) => error) ??
        phasesValue.whenOrNull(error: (error, _) => error);
    final canCreateChecklist = selectedCategory != null && selectedPhase != null;

    return Scaffold(
      appBar: AppBar(
        leading: const OperationsBackButton(fallbackRoute: Routes.operaciones),
        title: const Text('Configuración de Checklist'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: metadataLoading && _loading ? null : _refreshMetadataAndTemplates,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
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
            onRefresh: _refreshMetadataAndTemplates,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    _AdminHeroCard(
                      categoriesCount: categories.length,
                      phasesCount: phases.length,
                      templatesCount: _templates.length,
                    ),
                    const SizedBox(height: 16),
                    _FilterCard(
                      categories: categories,
                      phases: phases,
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
                    if (metadataError != null)
                      _ErrorCard(
                        message: metadataError is ApiException
                            ? metadataError.message
                            : 'No se pudo cargar la metadata de categorías/fases',
                        onRetry: _refreshMetadataAndTemplates,
                      ),
                    if (_error != null)
                      _ErrorCard(message: _error!, onRetry: _refreshMetadataAndTemplates),
                    if (canCreateChecklist)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _openCreateChecklistDialog,
                            icon: const Icon(Icons.playlist_add_check_circle_outlined),
                            label: const Text('Crear checklist'),
                          ),
                        ),
                      ),
                    if (metadataLoading || _loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!metadataLoading && !_loading && _error == null && selectedCategory != null && selectedPhase != null)
                      ..._sectionTypes.map(
                        (type) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ChecklistSectionAdminCard(
                            type: type,
                            categoryLabel: selectedCategory.name,
                            phaseLabel: selectedPhase.name,
                            template: _templateForType(type),
                            busy: _saving,
                            onCreateSection: _openCreateChecklistDialog,
                            onAddItem: (template) => _createItem(template),
                          ),
                        ),
                      ),
                    if (!metadataLoading && !_loading && _error == null && (selectedCategory == null || selectedPhase == null))
                      const _EmptyChecklistCard(
                        categoryLabel: null,
                        onCreateChecklist: null,
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

  const _AdminHeroCard({
    required this.categoriesCount,
    required this.phasesCount,
    required this.templatesCount,
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
            'Las categorías y fases se leen directamente desde Operaciones. Aquí solo eliges la combinación correcta y configuras Herramientas, Productos e Instalación.',
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
              _StatPill(label: 'Secciones activas', value: '$templatesCount'),
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
  final ValueChanged<String?> onPhaseChanged;

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
          DropdownButtonFormField<String>(
            initialValue: selectedPhaseId,
            items: phases
                .map(
                  (phase) => DropdownMenuItem<String>(
                    value: phase.id,
                    child: Text(phase.name),
                  ),
                )
                .toList(growable: false),
            onChanged: onPhaseChanged,
            decoration: const InputDecoration(
              labelText: 'Fase operativa',
              prefixIcon: Icon(Icons.layers_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistSectionAdminCard extends StatelessWidget {
  final ServiceChecklistSectionType type;
  final String categoryLabel;
  final String phaseLabel;
  final ServiceChecklistTemplateModel? template;
  final bool busy;
  final VoidCallback onCreateSection;
  final ValueChanged<ServiceChecklistTemplateModel> onAddItem;

  const _ChecklistSectionAdminCard({
    required this.type,
    required this.categoryLabel,
    required this.phaseLabel,
    required this.template,
    required this.busy,
    required this.onCreateSection,
    required this.onAddItem,
  });

  @override
  Widget build(BuildContext context) {
    if (template == null) {
      return _EmptyChecklistCard(
        categoryLabel:
            '$categoryLabel · $phaseLabel · ${serviceChecklistSectionTypeLabel(type)}',
        onCreateChecklist: busy ? null : onCreateSection,
      );
    }

    return _ChecklistTemplateAdminCard(
      template: template!,
      onAddItem: busy ? null : () => onAddItem(template!),
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
                      serviceChecklistSectionTypeLabel(template.type),
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
                        _MetaChip(label: template.title),
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
            categoryLabel == null
                ? 'Selecciona una categoría y una fase para empezar.'
                : 'No hay sección creada para $categoryLabel.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            categoryLabel == null
                ? 'El checklist siempre se configura usando la metadata existente del módulo de Operaciones.'
                : 'Crea esta sección para empezar a controlar herramientas, productos o instalación sin duplicar categorías ni fases.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onCreateChecklist != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreateChecklist,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Crear checklist'),
            ),
          ],
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

class _InlineHintCard extends StatelessWidget {
  final String text;

  const _InlineHintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CreateChecklistPayload {
  final ServiceChecklistSectionType type;
  final List<_CreateItemPayload> items;

  const _CreateChecklistPayload({required this.type, required this.items});
}

class _CreateItemPayload {
  final String label;
  final bool isRequired;
  final int orderIndex;

  const _CreateItemPayload({
    required this.label,
    required this.isRequired,
    required this.orderIndex,
  });
}
