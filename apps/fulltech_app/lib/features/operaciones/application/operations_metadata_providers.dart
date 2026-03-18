import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
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

class ChecklistMetadataDiagnostics {
  final ApiException? categoriesError;
  final ApiException? phasesError;
  final bool usingFallbackCategories;
  final bool usingFallbackPhases;

  const ChecklistMetadataDiagnostics({
    this.categoriesError,
    this.phasesError,
    this.usingFallbackCategories = false,
    this.usingFallbackPhases = false,
  });

  ChecklistMetadataDiagnostics copyWith({
    ApiException? categoriesError,
    ApiException? phasesError,
    bool? usingFallbackCategories,
    bool? usingFallbackPhases,
    bool clearCategoriesError = false,
    bool clearPhasesError = false,
  }) {
    return ChecklistMetadataDiagnostics(
      categoriesError: clearCategoriesError
          ? null
          : (categoriesError ?? this.categoriesError),
      phasesError: clearPhasesError
          ? null
          : (phasesError ?? this.phasesError),
      usingFallbackCategories:
          usingFallbackCategories ?? this.usingFallbackCategories,
      usingFallbackPhases: usingFallbackPhases ?? this.usingFallbackPhases,
    );
  }
}

final checklistMetadataDiagnosticsProvider =
    StateProvider<ChecklistMetadataDiagnostics>((ref) {
      return const ChecklistMetadataDiagnostics();
    });

final categoriesProvider = FutureProvider<List<ServiceChecklistCategoryModel>>((
  ref,
) async {
  final repo = ref.read(operationsRepositoryProvider);
  final cached = await repo.getCachedChecklistCategories();
  if (cached != null && cached.isNotEmpty) {
    ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
        .read(checklistMetadataDiagnosticsProvider)
        .copyWith(
          clearCategoriesError: true,
          usingFallbackCategories: false,
        );
    unawaited(() async {
      try {
        await repo.listChecklistCategoriesFast();
      } catch (error) {
        if (error is! ApiException) return;
        ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
            .read(checklistMetadataDiagnosticsProvider)
            .copyWith(
              categoriesError: error,
              usingFallbackCategories: true,
            );
      }
    }());
    final safeCached = _sanitizeOperationCategories(cached);
    return safeCached.isNotEmpty ? safeCached : defaultCategories;
  }

  try {
    final categories = await repo.listChecklistCategoriesFast();
    final safeCategories = categories.isNotEmpty
        ? _sanitizeOperationCategories(categories)
        : defaultCategories;
    ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
        .read(checklistMetadataDiagnosticsProvider)
        .copyWith(
          clearCategoriesError: true,
          usingFallbackCategories: categories.isEmpty,
        );
    return safeCategories.isNotEmpty ? safeCategories : defaultCategories;
  } catch (error) {
    ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
        .read(checklistMetadataDiagnosticsProvider)
        .copyWith(
          categoriesError: error is ApiException
              ? error
              : ApiException(
                  'No se pudieron cargar las categorías de checklist.',
                ),
          usingFallbackCategories: true,
        );
    return defaultCategories;
  }
});

final servicePhasesProvider = FutureProvider<List<ServiceChecklistPhaseModel>>((
  ref,
) async {
  final repo = ref.read(operationsRepositoryProvider);
  final cached = await repo.getCachedChecklistPhases();
  if (cached != null && cached.isNotEmpty) {
    ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
        .read(checklistMetadataDiagnosticsProvider)
        .copyWith(clearPhasesError: true, usingFallbackPhases: false);
    unawaited(() async {
      try {
        await repo.listChecklistPhasesFast();
      } catch (error) {
        if (error is! ApiException) return;
        ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
            .read(checklistMetadataDiagnosticsProvider)
            .copyWith(phasesError: error, usingFallbackPhases: true);
      }
    }());
    final safeCached = _sanitizeOperationPhases(cached);
    return safeCached.isNotEmpty ? safeCached : defaultPhases;
  }

  try {
    final phases = await repo.listChecklistPhasesFast();
    final safePhases = phases.isNotEmpty
        ? _sanitizeOperationPhases(phases)
        : defaultPhases;
    ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
        .read(checklistMetadataDiagnosticsProvider)
        .copyWith(
          clearPhasesError: true,
          usingFallbackPhases: phases.isEmpty,
        );
    return safePhases.isNotEmpty ? safePhases : defaultPhases;
  } catch (error) {
    ref.read(checklistMetadataDiagnosticsProvider.notifier).state = ref
        .read(checklistMetadataDiagnosticsProvider)
        .copyWith(
          phasesError: error is ApiException
              ? error
              : ApiException('No se pudieron cargar las fases de checklist.'),
          usingFallbackPhases: true,
        );
    return defaultPhases;
  }
});
