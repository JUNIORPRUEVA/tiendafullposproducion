import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/operations_repository.dart';
import '../operations_models.dart';

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
  ServiceChecklistCategoryModel(
    id: 'alarm',
    name: 'Alarma',
    code: 'alarm',
  ),
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
  try {
    final categories = await ref
        .read(operationsRepositoryProvider)
        .listChecklistCategories();
    final safeCategories = categories.isNotEmpty ? categories : defaultCategories;
    // ignore: avoid_print
    print('Categorias cargadas: ${categories.length}');
    // ignore: avoid_print
    print('Usando fallback categorias: ${categories.isEmpty}');
    return safeCategories;
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
  try {
    final phases = await ref
        .read(operationsRepositoryProvider)
        .listChecklistPhases();
    final safePhases = phases.isNotEmpty ? phases : defaultPhases;
    // ignore: avoid_print
    print('Fases cargadas: ${phases.length}');
    // ignore: avoid_print
    print('Usando fallback fases: ${phases.isEmpty}');
    return safePhases;
  } catch (_) {
    // ignore: avoid_print
    print('Fases cargadas: 0');
    // ignore: avoid_print
    print('Usando fallback fases: true');
    return defaultPhases;
  }
});
