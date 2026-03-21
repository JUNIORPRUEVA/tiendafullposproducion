import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../operations_models.dart';

enum TechOrderStatusFilter { pending, inProgress, completed }

enum TechOrderPhaseFilter { installation, maintenance, survey, warranty }

class TechOperationsFilterState {
  final Set<TechOrderStatusFilter> statuses;
  final Set<TechOrderPhaseFilter> phases;

  const TechOperationsFilterState({
    this.statuses = const <TechOrderStatusFilter>{},
    this.phases = const <TechOrderPhaseFilter>{},
  });

  bool get hasActiveFilters => statuses.isNotEmpty || phases.isNotEmpty;

  TechOperationsFilterState copyWith({
    Set<TechOrderStatusFilter>? statuses,
    Set<TechOrderPhaseFilter>? phases,
  }) {
    return TechOperationsFilterState(
      statuses: statuses ?? this.statuses,
      phases: phases ?? this.phases,
    );
  }
}

class TechOperationsFilterController
    extends StateNotifier<TechOperationsFilterState> {
  TechOperationsFilterController() : super(const TechOperationsFilterState());

  void toggleStatus(TechOrderStatusFilter filter) {
    final next = Set<TechOrderStatusFilter>.from(state.statuses);
    if (!next.add(filter)) {
      next.remove(filter);
    }
    state = state.copyWith(statuses: next);
  }

  void togglePhase(TechOrderPhaseFilter filter) {
    final next = Set<TechOrderPhaseFilter>.from(state.phases);
    if (!next.add(filter)) {
      next.remove(filter);
    }
    state = state.copyWith(phases: next);
  }

  void clear() {
    if (!state.hasActiveFilters) return;
    state = const TechOperationsFilterState();
  }
}

final techOperationsFilterProvider =
    StateNotifierProvider<
      TechOperationsFilterController,
      TechOperationsFilterState
    >((ref) {
      return TechOperationsFilterController();
    });

class TechOperationsSummary {
  final int totalVisible;
  final int pendingCount;
  final int inProgressCount;
  final int completedCount;
  final int urgentCount;
  final int primaryCount;

  const TechOperationsSummary({
    required this.totalVisible,
    required this.pendingCount,
    required this.inProgressCount,
    required this.completedCount,
    required this.urgentCount,
    required this.primaryCount,
  });
}

String normalizeTechKey(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.isEmpty) return '';

  value = value
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');

  return value.replaceAll(' ', '_').replaceAll('-', '_');
}

String techOrderStatusLabel(TechOrderStatusFilter filter) {
  switch (filter) {
    case TechOrderStatusFilter.pending:
      return 'Pendiente';
    case TechOrderStatusFilter.inProgress:
      return 'En proceso';
    case TechOrderStatusFilter.completed:
      return 'Finalizado';
  }
}

IconData techOrderStatusIcon(TechOrderStatusFilter filter) {
  switch (filter) {
    case TechOrderStatusFilter.pending:
      return Icons.schedule_rounded;
    case TechOrderStatusFilter.inProgress:
      return Icons.autorenew_rounded;
    case TechOrderStatusFilter.completed:
      return Icons.verified_rounded;
  }
}

Color techOrderStatusColor(TechOrderStatusFilter filter) {
  switch (filter) {
    case TechOrderStatusFilter.pending:
      return const Color(0xFFC77800);
    case TechOrderStatusFilter.inProgress:
      return const Color(0xFF0B6BDE);
    case TechOrderStatusFilter.completed:
      return const Color(0xFF15803D);
  }
}

String techOrderPhaseLabel(TechOrderPhaseFilter filter) {
  switch (filter) {
    case TechOrderPhaseFilter.installation:
      return 'Instalación';
    case TechOrderPhaseFilter.maintenance:
      return 'Mantenimiento';
    case TechOrderPhaseFilter.survey:
      return 'Levantamiento';
    case TechOrderPhaseFilter.warranty:
      return 'Garantía';
  }
}

IconData techOrderPhaseIcon(TechOrderPhaseFilter filter) {
  switch (filter) {
    case TechOrderPhaseFilter.installation:
      return Icons.bolt_rounded;
    case TechOrderPhaseFilter.maintenance:
      return Icons.tune_rounded;
    case TechOrderPhaseFilter.survey:
      return Icons.rule_folder_rounded;
    case TechOrderPhaseFilter.warranty:
      return Icons.workspace_premium_rounded;
  }
}

Color techOrderPhaseColor(TechOrderPhaseFilter filter) {
  switch (filter) {
    case TechOrderPhaseFilter.installation:
      return const Color(0xFF0B6BDE);
    case TechOrderPhaseFilter.maintenance:
      return const Color(0xFF138A5B);
    case TechOrderPhaseFilter.survey:
      return const Color(0xFF8A5A14);
    case TechOrderPhaseFilter.warranty:
      return const Color(0xFF5B6CFF);
  }
}

String techServiceCategoryLabel(ServiceModel service) {
  return service.categoryLabel;
}

TechOrderPhaseFilter? techOrderPhaseFrom(ServiceModel service) {
  final candidates = [
    service.currentPhase,
    service.serviceType,
    service.orderType,
    service.title,
    service.description,
  ];

  for (final candidate in candidates) {
    final key = normalizeTechKey(candidate);
    if (key.contains('instalacion') || key.contains('installation')) {
      return TechOrderPhaseFilter.installation;
    }
    if (key.contains('mantenimiento') || key.contains('maintenance')) {
      return TechOrderPhaseFilter.maintenance;
    }
    if (key.contains('levantamiento') || key.contains('survey')) {
      return TechOrderPhaseFilter.survey;
    }
    if (key.contains('garantia') || key.contains('warranty')) {
      return TechOrderPhaseFilter.warranty;
    }
  }

  return null;
}

TechOrderStatusFilter techOrderStatusFrom(ServiceModel service) {
  final rawStatus = service.orderState.trim().isEmpty
      ? service.status
      : service.orderState;
  final status = parseStatus(rawStatus);

  switch (status) {
    case ServiceStatus.inProgress:
    case ServiceStatus.warranty:
      return TechOrderStatusFilter.inProgress;
    case ServiceStatus.completed:
    case ServiceStatus.closed:
    case ServiceStatus.cancelled:
      return TechOrderStatusFilter.completed;
    case ServiceStatus.reserved:
    case ServiceStatus.scheduled:
    case ServiceStatus.survey:
    case ServiceStatus.unknown:
      return TechOrderStatusFilter.pending;
  }
}

bool isReservationTechOrder(ServiceModel service) {
  final hasScheduling =
      service.scheduledStart != null || service.scheduledEnd != null;
  final hasTechnician = (service.technicianId ?? '').trim().isNotEmpty;
  final hasAssignments = service.assignments.isNotEmpty;
  final hasCompletion = service.completedAt != null;

  final candidates = [
    service.orderType,
    service.currentPhase,
    service.serviceType,
    service.status,
    service.orderState,
  ];

  final hasReservationHint = candidates.any((candidate) {
    final key = normalizeTechKey(candidate);
    return key.contains('reserva') || key.contains('reserv');
  });

  return hasReservationHint &&
      !hasScheduling &&
      !hasTechnician &&
      !hasAssignments &&
      !hasCompletion;
}

bool isPrimaryTechOrder(ServiceModel service) {
  final phase = techOrderPhaseFrom(service);
  return phase == TechOrderPhaseFilter.installation ||
      phase == TechOrderPhaseFilter.maintenance;
}

bool isUrgentTechOrder(ServiceModel service, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final scheduled = service.scheduledStart ?? service.scheduledEnd;
  final hasHighPriority = service.priority >= 8;
  final isSameDay =
      scheduled != null &&
      scheduled.toLocal().year == reference.year &&
      scheduled.toLocal().month == reference.month &&
      scheduled.toLocal().day == reference.day;

  return techOrderStatusFrom(service) != TechOrderStatusFilter.completed &&
      (hasHighPriority || isSameDay);
}

String techServiceHeadline(ServiceModel service) {
  final phase = techOrderPhaseFrom(service);
  final category = techServiceCategoryLabel(service);
  final title = service.title.trim();

  final phaseLabel = phase == null ? '' : techOrderPhaseLabel(phase);
  if (category.isNotEmpty && phaseLabel.isNotEmpty) {
    return '$phaseLabel • $category';
  }
  if (category.isNotEmpty) return category;
  if (phaseLabel.isNotEmpty) return phaseLabel;
  if (title.isNotEmpty) return title;
  return 'Servicio técnico';
}

List<ServiceModel> filterTechOrders(
  List<ServiceModel> services,
  TechOperationsFilterState filters,
) {
  final filtered = services
      .where((service) => !isReservationTechOrder(service))
      .where((service) {
        final status = techOrderStatusFrom(service);
        final phase = techOrderPhaseFrom(service);

        final matchesStatus =
            filters.statuses.isEmpty || filters.statuses.contains(status);
        final matchesPhase =
            filters.phases.isEmpty ||
            (phase != null && filters.phases.contains(phase));

        return matchesStatus && matchesPhase;
      })
      .toList(growable: false);

  int sortWeight(ServiceModel service) {
    var weight = 0;
    if (isUrgentTechOrder(service)) weight += 1000;

    final status = techOrderStatusFrom(service);
    switch (status) {
      case TechOrderStatusFilter.pending:
        weight += 500;
        break;
      case TechOrderStatusFilter.inProgress:
        weight += 350;
        break;
      case TechOrderStatusFilter.completed:
        weight += 100;
        break;
    }

    if (isPrimaryTechOrder(service)) weight += 150;
    weight += service.priority.clamp(0, 999);
    return weight;
  }

  filtered.sort((left, right) {
    final weightCompare = sortWeight(right).compareTo(sortWeight(left));
    if (weightCompare != 0) return weightCompare;

    final leftScheduled =
        (left.scheduledStart ?? left.scheduledEnd)?.millisecondsSinceEpoch ?? 0;
    final rightScheduled =
        (right.scheduledStart ?? right.scheduledEnd)?.millisecondsSinceEpoch ??
        0;
    final scheduleCompare = leftScheduled.compareTo(rightScheduled);
    if (scheduleCompare != 0) return scheduleCompare;

    return left.customerName.toLowerCase().compareTo(
      right.customerName.toLowerCase(),
    );
  });

  return filtered;
}

TechOperationsSummary summarizeTechOrders(List<ServiceModel> services) {
  final visible = services.where((service) => !isReservationTechOrder(service));

  var totalVisible = 0;
  var pendingCount = 0;
  var inProgressCount = 0;
  var completedCount = 0;
  var urgentCount = 0;
  var primaryCount = 0;

  for (final service in visible) {
    totalVisible += 1;

    final status = techOrderStatusFrom(service);
    if (status == TechOrderStatusFilter.pending) pendingCount += 1;
    if (status == TechOrderStatusFilter.inProgress) inProgressCount += 1;
    if (status == TechOrderStatusFilter.completed) completedCount += 1;
    if (isUrgentTechOrder(service)) urgentCount += 1;
    if (isPrimaryTechOrder(service)) primaryCount += 1;
  }

  return TechOperationsSummary(
    totalVisible: totalVisible,
    pendingCount: pendingCount,
    inProgressCount: inProgressCount,
    completedCount: completedCount,
    urgentCount: urgentCount,
    primaryCount: primaryCount,
  );
}

Map<TechOrderStatusFilter, int> buildStatusCounts(List<ServiceModel> services) {
  final counts = {for (final filter in TechOrderStatusFilter.values) filter: 0};

  for (final service in services) {
    if (isReservationTechOrder(service)) continue;
    final filter = techOrderStatusFrom(service);
    counts[filter] = (counts[filter] ?? 0) + 1;
  }

  return counts;
}

Map<TechOrderPhaseFilter, int> buildPhaseCounts(List<ServiceModel> services) {
  final counts = {for (final filter in TechOrderPhaseFilter.values) filter: 0};

  for (final service in services) {
    if (isReservationTechOrder(service)) continue;
    final phase = techOrderPhaseFrom(service);
    if (phase == null) continue;
    counts[phase] = (counts[phase] ?? 0) + 1;
  }

  return counts;
}
