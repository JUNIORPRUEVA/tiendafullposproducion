import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import 'application/operations_metadata_providers.dart';
import 'data/operations_repository.dart';
import 'operations_models.dart';
import 'presentation/operations_back_button.dart';

class OperacionesWarrantyConfigScreen extends ConsumerStatefulWidget {
  const OperacionesWarrantyConfigScreen({super.key});

  @override
  ConsumerState<OperacionesWarrantyConfigScreen> createState() =>
      _OperacionesWarrantyConfigScreenState();
}

class _OperacionesWarrantyConfigScreenState
    extends ConsumerState<OperacionesWarrantyConfigScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _search = '';
  String? _selectedCategoryId;
  List<WarrantyProductConfigModel> _items = const [];

  bool get _canManage {
    final role = ref.read(authStateProvider).user?.appRole ?? AppRole.unknown;
    return role == AppRole.admin ||
        role == AppRole.asistente ||
        role == AppRole.vendedor;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(operationsRepositoryProvider)
          .listWarrantyProductConfigs(
            categoryId: _selectedCategoryId,
            search: _search,
            includeInactive: true,
          );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  ServiceChecklistCategoryModel? _findCategory(
    List<ServiceChecklistCategoryModel> categories,
    String? id,
  ) {
    if (id == null || id.trim().isEmpty) return null;
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Future<void> _openEditor({WarrantyProductConfigModel? item}) async {
    final categories = ref
        .read(categoriesProvider)
        .maybeWhen(data: (value) => value, orElse: () => defaultCategories);
    final productController = TextEditingController(
      text: item?.productName ?? '',
    );
    final summaryController = TextEditingController(
      text: item?.warrantySummary ?? '',
    );
    final coverageController = TextEditingController(
      text: item?.coverageSummary ?? '',
    );
    final exclusionsController = TextEditingController(
      text: item?.exclusionsSummary ?? '',
    );
    final notesController = TextEditingController(text: item?.notes ?? '');
    final durationController = TextEditingController(
      text: item?.durationValue?.toString() ?? '',
    );

    String? categoryId = item?.categoryId ?? _selectedCategoryId;
    var hasWarranty = item?.hasWarranty ?? true;
    var isActive = item?.isActive ?? true;
    var durationUnit = item?.durationUnit ?? WarrantyDurationUnitModel.months;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text(
                item == null
                    ? 'Nueva configuración de garantía'
                    : 'Editar garantía',
              ),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _findCategory(categories, categoryId)?.id,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                        ),
                        items: categories
                            .map(
                              (category) => DropdownMenuItem<String>(
                                value: category.id,
                                child: Text(
                                  localizedServiceCategoryLabel(
                                    category.code.trim().isNotEmpty
                                        ? category.code
                                        : category.name,
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setLocalState(() {
                            categoryId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: productController,
                        decoration: const InputDecoration(
                          labelText: 'Producto específico',
                          hintText: 'Opcional, prioriza coincidencia exacta',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Tiene garantía comercial'),
                        value: hasWarranty,
                        onChanged: (value) {
                          setLocalState(() {
                            hasWarranty = value;
                          });
                        },
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: durationController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Duración',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                                DropdownButtonFormField<
                                  WarrantyDurationUnitModel
                                >(
                                  initialValue: durationUnit,
                                  decoration: const InputDecoration(
                                    labelText: 'Unidad',
                                  ),
                                  items: WarrantyDurationUnitModel.values
                                      .map(
                                        (unit) => DropdownMenuItem(
                                          value: unit,
                                          child: Text(
                                            warrantyDurationUnitLabel(unit),
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setLocalState(() {
                                      durationUnit = value;
                                    });
                                  },
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: summaryController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Resumen ejecutivo',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: coverageController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Cobertura incluida',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: exclusionsController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Exclusiones y límites',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notas operativas',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Registro activo'),
                        value: isActive,
                        onChanged: (value) {
                          setLocalState(() {
                            isActive = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (_saving) return;
                    setState(() => _saving = true);
                    try {
                      final repo = ref.read(operationsRepositoryProvider);
                      final selectedCategory = _findCategory(
                        categories,
                        categoryId,
                      );
                      final durationValue = int.tryParse(
                        durationController.text.trim(),
                      );
                      if (item == null) {
                        await repo.createWarrantyProductConfig(
                          categoryId: categoryId,
                          categoryCode: selectedCategory?.code,
                          categoryName: selectedCategory?.name,
                          productName: productController.text,
                          hasWarranty: hasWarranty,
                          durationValue: durationValue,
                          durationUnit: hasWarranty ? durationUnit : null,
                          warrantySummary: summaryController.text,
                          coverageSummary: coverageController.text,
                          exclusionsSummary: exclusionsController.text,
                          notes: notesController.text,
                          isActive: isActive,
                        );
                      } else {
                        await repo.updateWarrantyProductConfig(
                          id: item.id,
                          categoryId: categoryId,
                          categoryCode: selectedCategory?.code,
                          categoryName: selectedCategory?.name,
                          productName: productController.text,
                          hasWarranty: hasWarranty,
                          durationValue: durationValue,
                          durationUnit: hasWarranty ? durationUnit : null,
                          warrantySummary: summaryController.text,
                          coverageSummary: coverageController.text,
                          exclusionsSummary: exclusionsController.text,
                          notes: notesController.text,
                          isActive: isActive,
                        );
                      }
                      if (!mounted) return;
                      setState(() => _saving = false);
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop(true);
                    } on ApiException catch (error) {
                      if (!mounted) return;
                      setState(() => _saving = false);
                      if (!dialogContext.mounted) return;
                      await AppFeedback.showError(
                        dialogContext,
                        error.message,
                        fallbackContext: dialogContext,
                        scope: 'WarrantyConfigScreen',
                      );
                    } catch (error) {
                      if (!mounted) return;
                      setState(() => _saving = false);
                      if (!dialogContext.mounted) return;
                      await AppFeedback.showError(
                        dialogContext,
                        '$error',
                        fallbackContext: dialogContext,
                        scope: 'WarrantyConfigScreen',
                      );
                    }
                  },
                  child: Text(item == null ? 'Crear' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    productController.dispose();
    summaryController.dispose();
    coverageController.dispose();
    exclusionsController.dispose();
    notesController.dispose();
    durationController.dispose();

    if (saved == true) {
      await _load();
      if (mounted) {
        await AppFeedback.showInfo(
          context,
          'Configuración de garantía guardada.',
          scope: 'WarrantyConfigScreen',
        );
      }
    }
  }

  Future<void> _toggleActive(
    WarrantyProductConfigModel item,
    bool isActive,
  ) async {
    try {
      await ref
          .read(operationsRepositoryProvider)
          .setWarrantyProductConfigActive(id: item.id, isActive: isActive);
      await _load();
    } catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        '$error',
        scope: 'WarrantyConfigScreen',
      );
    }
  }

  Future<void> _delete(WarrantyProductConfigModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar configuración'),
        content: Text('Se eliminará ${item.scopeLabel}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(operationsRepositoryProvider)
          .deleteWarrantyProductConfig(item.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        '$error',
        scope: 'WarrantyConfigScreen',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref
        .watch(categoriesProvider)
        .maybeWhen(data: (items) => items, orElse: () => defaultCategories);

    return Scaffold(
      appBar: AppBar(
        leading: const OperationsBackButton(fallbackRoute: Routes.operaciones),
        title: const Text('Garantías operativas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva garantía'),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configura coberturas por producto o categoría. La carta PDF prioriza coincidencia exacta por producto y usa la categoría como fallback.',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Buscar producto o texto',
                            ),
                            onChanged: (value) => _search = value,
                            onSubmitted: (_) => _load(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _findCategory(
                              categories,
                              _selectedCategoryId,
                            )?.id,
                            decoration: const InputDecoration(
                              labelText: 'Categoría',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Todas'),
                              ),
                              ...categories.map(
                                (category) => DropdownMenuItem<String>(
                                  value: category.id,
                                  child: Text(
                                    localizedServiceCategoryLabel(
                                      category.code.trim().isNotEmpty
                                          ? category.code
                                          : category.name,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedCategoryId =
                                    (value ?? '').trim().isEmpty ? null : value;
                              });
                              _load();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.filter_alt_outlined),
                          label: const Text('Aplicar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay configuraciones de garantía registradas.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.scopeLabel,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                              if ((item.categoryName ?? '')
                                                  .trim()
                                                  .isNotEmpty)
                                                item.categoryName,
                                              item.durationLabel,
                                              item.isActive
                                                  ? 'Activa'
                                                  : 'Inactiva',
                                            ].whereType<String>().join(' · '),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: item.isActive,
                                      onChanged: _canManage
                                          ? (value) =>
                                                _toggleActive(item, value)
                                          : null,
                                    ),
                                  ],
                                ),
                                if ((item.warrantySummary ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(item.warrantySummary!),
                                  ),
                                if ((item.coverageSummary ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Cobertura: ${item.coverageSummary!}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                if ((item.exclusionsSummary ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Exclusiones: ${item.exclusionsSummary!}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _canManage
                                          ? () => _openEditor(item: item)
                                          : null,
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Editar'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: _canManage
                                          ? () => _delete(item)
                                          : null,
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Eliminar'),
                                    ),
                                  ],
                                ),
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
}
