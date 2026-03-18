import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/operations_repository.dart';
import '../operations_models.dart';

const _allowedOperationPhaseCodes = <String>{
  'reserva',
  'instalacion',
  'mantenimiento',
  'garantia',
  'levantamiento',
};

bool _isSupportedOperationCategory(ServiceChecklistCategoryModel item) {
  final values = <String>[
    item.id.trim().toLowerCase(),
    item.code.trim().toLowerCase(),
    item.name.trim().toLowerCase(),
  ];
  return values.any((value) => value.isNotEmpty && value != 'general');
}

bool _isSupportedOperationPhase(ServiceChecklistPhaseModel item) {
  final code = item.code.trim().toLowerCase();
  final id = item.id.trim().toLowerCase();
  return _allowedOperationPhaseCodes.contains(code) ||
      _allowedOperationPhaseCodes.contains(id);
}

List<ServiceChecklistCategoryModel> _sanitizeOperationCategories(
  List<ServiceChecklistCategoryModel> items,
) {
  return items.where(_isSupportedOperationCategory).toList(growable: false);
}

List<ServiceChecklistPhaseModel> _sanitizeOperationPhases(
  List<ServiceChecklistPhaseModel> items,
) {
  final filtered = items
      .where(_isSupportedOperationPhase)
      .toList(growable: false);
  filtered.sort((left, right) => left.orderIndex.compareTo(right.orderIndex));
  return filtered;
}

const defaultCategories = <ServiceChecklistCategoryModel>[
  ServiceChecklistCategoryModel(
    id: 'cameras',
    name: 'Cámaras',
    code: 'cameras',
  ),
  ServiceChecklistCategoryModel(
    id: 'gate_motor',
    name: 'Motores de portones',
    code: 'gate_motor',
  ),
  ServiceChecklistCategoryModel(id: 'alarm', name: 'Alarma', code: 'alarm'),
  ServiceChecklistCategoryModel(
    id: 'electric_fence',
    name: 'Cerco eléctrico',
    code: 'electric_fence',
  ),
  ServiceChecklistCategoryModel(
    id: 'intercom',
    name: 'Intercom',
    code: 'intercom',
  ),
  ServiceChecklistCategoryModel(
    id: 'pos',
    name: 'Punto de ventas',
    code: 'pos',
  ),
];

const defaultPhases = <ServiceChecklistPhaseModel>[
  ServiceChecklistPhaseModel(
    id: 'reserva',
    name: 'Reserva',
    code: 'reserva',
    orderIndex: 0,
  ),
  ServiceChecklistPhaseModel(
    id: 'instalacion',
    name: 'Instalación',
    code: 'instalacion',
    orderIndex: 1,
  ),
  ServiceChecklistPhaseModel(
    id: 'mantenimiento',
    name: 'Mantenimiento',
    code: 'mantenimiento',
    orderIndex: 2,
  ),
  ServiceChecklistPhaseModel(
    id: 'garantia',
    name: 'Garantía',
    code: 'garantia',
    orderIndex: 3,
  ),
  ServiceChecklistPhaseModel(
    id: 'levantamiento',
    name: 'Levantamiento',
    code: 'levantamiento',
    orderIndex: 4,
  ),
];

final categoriesProvider = FutureProvider<List<ServiceChecklistCategoryModel>>((
  ref,
) async {
  final repo = ref.read(operationsRepositoryProvider);
  final cached = await repo.getCachedChecklistCategories();
  if (cached != null && cached.isNotEmpty) {
    unawaited(repo.listChecklistCategoriesFast());
    final safeCached = _sanitizeOperationCategories(cached);
    return safeCached.isNotEmpty ? safeCached : defaultCategories;
  }

  try {
    final categories = await repo.listChecklistCategoriesFast();
    final safeCategories = categories.isNotEmpty
        ? _sanitizeOperationCategories(categories)
        : defaultCategories;
    // ignore: avoid_print
    print('Categorias cargadas: ${categories.length}');
    // ignore: avoid_print
    print('Usando fallback categorias: ${categories.isEmpty}');
    return safeCategories.isNotEmpty ? safeCategories : defaultCategories;
  } catch (_) {
    // ignore: avoid_print
    print('Categorias cargadas: 0');
    // ignore: avoid_print
    print('Usando fallback categorias: true');
    return defaultCategories;
  }
});

final servicePhasesProvider = FutureProvider<List<ServiceChecklistPhaseModel>>((
  ref,
) async {
  final repo = ref.read(operationsRepositoryProvider);
  final cached = await repo.getCachedChecklistPhases();
  if (cached != null && cached.isNotEmpty) {
    unawaited(repo.listChecklistPhasesFast());
    final safeCached = _sanitizeOperationPhases(cached);
    return safeCached.isNotEmpty ? safeCached : defaultPhases;
  }

  try {
    final phases = await repo.listChecklistPhasesFast();
    final safePhases = phases.isNotEmpty
        ? _sanitizeOperationPhases(phases)
        : defaultPhases;
    // ignore: avoid_print
    print('Fases cargadas: ${phases.length}');
    // ignore: avoid_print
    print('Usando fallback fases: ${phases.isEmpty}');
    return safePhases.isNotEmpty ? safePhases : defaultPhases;
  } catch (_) {
    // ignore: avoid_print
    print('Fases cargadas: 0');
    // ignore: avoid_print
    print('Usando fallback fases: true');
    return defaultPhases;
  }
});
