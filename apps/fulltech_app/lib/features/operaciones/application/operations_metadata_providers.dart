import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/operations_repository.dart';
import '../operations_models.dart';

final categoriesProvider = FutureProvider<List<ServiceChecklistCategoryModel>>((
  ref,
) async {
  final categories = await ref
      .read(operationsRepositoryProvider)
      .listChecklistCategories();
  debugPrint('Categorias cargadas: ${categories.length}');
  return categories;
});

final servicePhasesProvider = FutureProvider<List<ServiceChecklistPhaseModel>>((
  ref,
) async {
  final phases = await ref
      .read(operationsRepositoryProvider)
      .listChecklistPhases();
  debugPrint('Fases cargadas: ${phases.length}');
  return phases;
});
