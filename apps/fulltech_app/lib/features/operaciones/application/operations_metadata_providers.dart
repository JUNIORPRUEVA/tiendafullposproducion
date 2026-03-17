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

final categoriesProvider = FutureProvider<List<ServiceChecklistCategoryModel>>((
  ref,
) async {
  final categories = await ref
      .read(operationsRepositoryProvider)
      .listChecklistCategories();
  // ignore: avoid_print
  print('Categorias cargadas: ${categories.length}');
  return categories;
});

final servicePhasesProvider = FutureProvider<List<ServiceChecklistPhaseModel>>((
  ref,
) async {
  final phases = await ref
      .read(operationsRepositoryProvider)
      .listChecklistPhases();
  // ignore: avoid_print
  print('Fases cargadas: ${phases.length}');
  return phases;
});
