import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../modules/clientes/cliente_model.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';

class OperationsState {
  final bool loading;
  final String? error;
  final List<ServiceModel> services;
  final OperationsDashboardModel dashboard;
  final String search;
  final String? statusFilter;
  final String? typeFilter;
  final String? orderTypeFilter;
  final String? orderStateFilter;
  final String? technicianIdFilter;
  final int? priorityFilter;
  final String? customerIdFilter;
  final DateTime? from;
  final DateTime? to;

  const OperationsState({
    this.loading = false,
    this.error,
    this.services = const [],
    required this.dashboard,
    this.search = '',
    this.statusFilter,
    this.typeFilter,
    this.orderTypeFilter,
    this.orderStateFilter,
    this.technicianIdFilter,
    this.priorityFilter,
    this.customerIdFilter,
    this.from,
    this.to,
  });

  factory OperationsState.initial() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return OperationsState(
      dashboard: OperationsDashboardModel.empty(),
      from: start,
      to: end,
    );
  }

  OperationsState copyWith({
    bool? loading,
    String? error,
    List<ServiceModel>? services,
    OperationsDashboardModel? dashboard,
    String? search,
    String? statusFilter,
    String? typeFilter,
    String? orderTypeFilter,
    String? orderStateFilter,
    String? technicianIdFilter,
    int? priorityFilter,
    String? customerIdFilter,
    DateTime? from,
    DateTime? to,
    bool clearError = false,
    bool clearStatus = false,
    bool clearType = false,
    bool clearOrderType = false,
    bool clearOrderState = false,
    bool clearTechnician = false,
    bool clearPriority = false,
    bool clearCustomer = false,
  }) {
    return OperationsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      services: services ?? this.services,
      dashboard: dashboard ?? this.dashboard,
      search: search ?? this.search,
      statusFilter: clearStatus ? null : (statusFilter ?? this.statusFilter),
      typeFilter: clearType ? null : (typeFilter ?? this.typeFilter),
      orderTypeFilter: clearOrderType
          ? null
          : (orderTypeFilter ?? this.orderTypeFilter),
      orderStateFilter: clearOrderState
          ? null
          : (orderStateFilter ?? this.orderStateFilter),
      technicianIdFilter: clearTechnician
          ? null
          : (technicianIdFilter ?? this.technicianIdFilter),
      priorityFilter: clearPriority
          ? null
          : (priorityFilter ?? this.priorityFilter),
      customerIdFilter: clearCustomer
          ? null
          : (customerIdFilter ?? this.customerIdFilter),
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }
}

final operationsControllerProvider =
    StateNotifierProvider<OperationsController, OperationsState>((ref) {
      return OperationsController(ref);
    });

class OperationsController extends StateNotifier<OperationsState> {
  final Ref ref;
  int _loadSeq = 0;

  OperationsController(this.ref) : super(OperationsState.initial()) {
    load();
  }

  Future<void> load() async {
    final seq = ++_loadSeq;
    final repo = ref.read(operationsRepositoryProvider);
    final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();

    try {
      final cached = await Future.wait([
        repo.getCachedServices(
          cacheScope: cacheScope,
          status: state.statusFilter,
          type: state.typeFilter,
          orderType: state.orderTypeFilter,
          orderState: state.orderStateFilter,
          technicianId: state.technicianIdFilter,
          priority: state.priorityFilter,
          customerId: state.customerIdFilter,
          search: state.search,
          from: state.from,
          to: state.to,
          page: 1,
          pageSize: 120,
        ),
        repo.getCachedDashboard(
          cacheScope: cacheScope,
          from: state.from,
          to: state.to,
        ),
      ]);

      final cachedPage = cached[0] as ServicesPageModel?;
      final cachedDashboard = cached[1] as OperationsDashboardModel?;
      final cachedItems = cachedPage?.items ?? const <ServiceModel>[];
      final hasCached = cachedItems.isNotEmpty || cachedDashboard != null;

      // Paint cache immediately (instant UI), then refresh in background.
      state = state.copyWith(
        loading: !hasCached && state.services.isEmpty,
        clearError: true,
        services: cachedPage?.items ?? state.services,
        dashboard: cachedDashboard ?? state.dashboard,
      );

      unawaited(() async {
        try {
          final results = await Future.wait([
            repo.listServicesAndCache(
              cacheScope: cacheScope,
              silent: true,
              status: state.statusFilter,
              type: state.typeFilter,
              orderType: state.orderTypeFilter,
              orderState: state.orderStateFilter,
              technicianId: state.technicianIdFilter,
              priority: state.priorityFilter,
              customerId: state.customerIdFilter,
              search: state.search,
              from: state.from,
              to: state.to,
              page: 1,
              pageSize: 120,
            ),
            repo.dashboardAndCache(
              cacheScope: cacheScope,
              silent: true,
              from: state.from,
              to: state.to,
            ),
          ]);

          if (!mounted || seq != _loadSeq) return;

          final page = results[0] as ServicesPageModel;
          final dashboard = results[1] as OperationsDashboardModel;
          state = state.copyWith(
            loading: false,
            services: page.items,
            dashboard: dashboard,
          );
        } catch (e) {
          if (!mounted || seq != _loadSeq) return;
          state = state.copyWith(
            loading: false,
            error: e is ApiException
                ? e.message
                : 'No se pudo cargar operaciones',
          );
        }
      }());
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e is ApiException ? e.message : 'No se pudo cargar operaciones',
      );
    }
  }

  Future<void> refresh() => load();

  void applyRealtimeService(ServiceModel service) {
    final before = state.services;
    if (before.isEmpty) return;
    final index = before.indexWhere((s) => s.id == service.id);
    if (index < 0) return;
    final next = [...before];
    next[index] = service;
    state = state.copyWith(services: next);
  }

  Future<void> setSearch(String value) async {
    state = state.copyWith(search: value);
    await load();
  }

  Future<void> setStatus(String? value) async {
    state = value == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(statusFilter: value);
    await load();
  }

  Future<void> setType(String? value) async {
    state = value == null
        ? state.copyWith(clearType: true)
        : state.copyWith(typeFilter: value);
    await load();
  }

  Future<void> setOrderType(String? value) async {
    state = value == null
        ? state.copyWith(clearOrderType: true)
        : state.copyWith(orderTypeFilter: value);
    await load();
  }

  Future<void> setOrderState(String? value) async {
    state = value == null
        ? state.copyWith(clearOrderState: true)
        : state.copyWith(orderStateFilter: value);
    await load();
  }

  Future<void> setTechnicianId(String? value) async {
    state = value == null
        ? state.copyWith(clearTechnician: true)
        : state.copyWith(technicianIdFilter: value);
    await load();
  }

  Future<void> applyRangeAndTechnician({
    required DateTime from,
    required DateTime to,
    required String? technicianId,
  }) async {
    var next = state.copyWith(from: from, to: to);
    next = (technicianId == null || technicianId.trim().isEmpty)
        ? next.copyWith(clearTechnician: true)
        : next.copyWith(technicianIdFilter: technicianId);
    state = next;
    await load();
  }

  Future<void> setPriority(int? value) async {
    state = value == null
        ? state.copyWith(clearPriority: true)
        : state.copyWith(priorityFilter: value);
    await load();
  }

  Future<void> setCustomer(String? customerId) async {
    state = customerId == null
        ? state.copyWith(clearCustomer: true)
        : state.copyWith(customerIdFilter: customerId);
    await load();
  }

  Future<void> setRange(DateTime from, DateTime to) async {
    state = state.copyWith(from: from, to: to);
    await load();
  }

  Future<ServiceModel> getOne(String id) async {
    final repo = ref.read(operationsRepositoryProvider);
    final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();

    final cached = await repo.getCachedService(cacheScope: cacheScope, id: id);
    if (cached != null) {
      unawaited(
        repo.getServiceAndCache(cacheScope: cacheScope, id: id, silent: true),
      );
      return cached;
    }

    return repo.getServiceAndCache(cacheScope: cacheScope, id: id, silent: true);
  }

  Future<ServiceModel> updateService({
    required String serviceId,
    String? description,
    String? addressSnapshot,
  }) async {
    final updated = await ref
        .read(operationsRepositoryProvider)
        .updateService(
          serviceId: serviceId,
          description: description,
          addressSnapshot: addressSnapshot,
        );
    await load();
    return updated;
  }

  Future<ServiceModel> createReservation({
    required String customerId,
    required String serviceType,
    required String category,
    required int priority,
    required String title,
    required String description,
    String? addressSnapshot,
    double? quotedAmount,
    double? depositAmount,
    String? orderType,
    String? orderState,
    String? technicianId,
    String? warrantyParentServiceId,
    String? surveyResult,
    String? materialsUsed,
    double? finalCost,
    List<String>? tags,
  }) async {
    final userId = (ref.read(authStateProvider).user?.id ?? '').trim();
    if (userId.isEmpty) {
      throw ApiException(
        'Debes iniciar sesión para crear una orden/servicio (firma requerida).',
        401,
      );
    }

    String? normalizeAdminStatus(String? raw) {
      final v = (raw ?? '').trim().toLowerCase();
      if (v.isEmpty) return null;
      const direct = {
        'pendiente',
        'confirmada',
        'asignada',
        'en_camino',
        'en_proceso',
        'finalizada',
        'reagendada',
        'cancelada',
        'cerrada',
      };
      if (direct.contains(v)) return v;

      // Legacy orderState values -> adminStatus
      switch (v) {
        case 'pending':
          return 'pendiente';
        case 'confirmed':
          return 'confirmada';
        case 'assigned':
          return 'asignada';
        case 'in_progress':
          return 'en_proceso';
        case 'finalized':
          return 'finalizada';
        case 'cancelled':
          return 'cancelada';
        case 'rescheduled':
          return 'reagendada';
        default:
          return null;
      }
    }

    String? legacyOrderStateForAdminStatus(String? raw) {
      final v = (raw ?? '').trim().toLowerCase();
      if (v.isEmpty) return null;
      switch (v) {
        case 'pendiente':
          return 'pending';
        case 'confirmada':
          return 'confirmed';
        case 'asignada':
          return 'assigned';
        case 'en_camino':
          return 'assigned';
        case 'en_proceso':
          return 'in_progress';
        case 'finalizada':
        case 'cerrada':
          return 'finalized';
        case 'cancelada':
          return 'cancelled';
        case 'reagendada':
          return 'rescheduled';
        default:
          return null;
      }
    }

    final adminStatus = normalizeAdminStatus(orderState);
    final hasTech = (technicianId ?? '').trim().isNotEmpty;
    final effectiveAdminStatus = adminStatus ?? (hasTech ? 'asignada' : 'pendiente');
    final legacyOrderState = legacyOrderStateForAdminStatus(effectiveAdminStatus);

    final normalizedType = (orderType ?? 'reserva').trim().toLowerCase();
    final effectiveAdminPhase = normalizedType == 'reserva'
      ? 'reserva'
      : 'programacion';

    final service = await ref.read(operationsRepositoryProvider).createService(
          customerId: customerId,
          serviceType: serviceType,
          category: category,
          priority: priority,
          title: title,
          description: description,
          addressSnapshot: addressSnapshot,
          quotedAmount: quotedAmount,
          depositAmount: depositAmount,
          orderType: orderType,
          orderState: legacyOrderState,
          adminPhase: effectiveAdminPhase,
          adminStatus: effectiveAdminStatus,
          technicianId: technicianId,
          warrantyParentServiceId: warrantyParentServiceId,
          surveyResult: surveyResult,
          materialsUsed: materialsUsed,
          finalCost: finalCost,
          tags: tags,
        );
    await load();
    return service;
  }

  Future<void> changeStatus(String id, String status, {String? message}) async {
    await ref
        .read(operationsRepositoryProvider)
        .changeStatus(serviceId: id, status: status, message: message);
    await load();
  }

  Future<void> changeOrderStateOptimistic(
    String id,
    String orderState, {
    String? message,
  }) async {
    final next = orderState.trim().toLowerCase();
    if (next.isEmpty) return;

    final before = state.services;
    final index = before.indexWhere((s) => s.id == id);

    if (index < 0) {
      await ref.read(operationsRepositoryProvider).changeAdminStatus(
            serviceId: id,
            adminStatus: next,
            message: message,
          );
      await load();
      return;
    }

    final current = before[index];
    if ((current.adminStatus ?? '').trim().toLowerCase() == next) return;

    final optimistic = current.copyWith(adminStatus: next);
    final optimisticList = [...before];
    optimisticList[index] = optimistic;
    state = state.copyWith(services: optimisticList);

    try {
      final updated = await ref
          .read(operationsRepositoryProvider)
          .changeAdminStatus(serviceId: id, adminStatus: next, message: message);

      final after = [...state.services];
      final idx = after.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        after[idx] = updated;
        state = state.copyWith(services: after);
      } else {
        await load();
      }
    } catch (e) {
      state = state.copyWith(services: before);
      rethrow;
    }
  }

  Future<ServiceModel> changeAdminPhaseOptimistic(
    String id,
    String adminPhase, {
    String? message,
  }) async {
    final next = adminPhase.trim().toLowerCase();
    if (next.isEmpty) {
      throw ApiException('Fase inválida', 400);
    }

    final before = state.services;
    final index = before.indexWhere((s) => s.id == id);

    if (index < 0) {
      final updated = await ref.read(operationsRepositoryProvider).changeAdminPhase(
            serviceId: id,
            adminPhase: next,
            message: message,
          );
      await load();
      return updated;
    }

    final current = before[index];
    if ((current.adminPhase ?? '').trim().toLowerCase() == next) return current;

    final optimistic = current.copyWith(adminPhase: next);
    final optimisticList = [...before];
    optimisticList[index] = optimistic;
    state = state.copyWith(services: optimisticList);

    try {
      final updated = await ref.read(operationsRepositoryProvider).changeAdminPhase(
            serviceId: id,
            adminPhase: next,
            message: message,
          );

      final after = [...state.services];
      final idx = after.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        after[idx] = updated;
        state = state.copyWith(services: after);
      }
      await load();
      return updated;
    } catch (e) {
      state = state.copyWith(services: before);
      rethrow;
    }
  }

  Future<ServiceModel> changePhaseOptimistic(
    String id,
    String phase, {
    required DateTime scheduledAt,
    String? note,
  }) async {
    final next = phase.trim().toLowerCase();
    if (next.isEmpty) {
      throw ApiException('Fase inválida', 400);
    }

    final before = state.services;
    final index = before.indexWhere((s) => s.id == id);

    if (index < 0) {
      final updated = await ref
          .read(operationsRepositoryProvider)
          .changePhase(
            serviceId: id,
            phase: next,
            scheduledAt: scheduledAt,
            note: note,
          );
      await load();
      return updated;
    }

    final current = before[index];
    if (current.currentPhase.trim().toLowerCase() == next) return current;

    final optimistic = current.copyWith(
      currentPhase: next,
      scheduledStart: scheduledAt,
    );
    final optimisticList = [...before];
    optimisticList[index] = optimistic;
    state = state.copyWith(services: optimisticList);

    try {
      final updated = await ref
          .read(operationsRepositoryProvider)
          .changePhase(
            serviceId: id,
            phase: next,
            scheduledAt: scheduledAt,
            note: note,
          );

      final after = [...state.services];
      final idx = after.indexWhere((s) => s.id == id);
      if (idx >= 0) {
        after[idx] = updated;
        state = state.copyWith(services: after);
      }

      // Ensure filters/counters reflect the new schedule.
      await load();
      return updated;
    } catch (e) {
      state = state.copyWith(services: before);
      rethrow;
    }
  }

  Future<void> schedule(
    String id,
    DateTime start,
    DateTime end, {
    String? message,
  }) async {
    await ref
        .read(operationsRepositoryProvider)
        .schedule(serviceId: id, start: start, end: end, message: message);
    await load();
  }

  Future<void> assign(String id, List<Map<String, String>> assignments) async {
    await ref
        .read(operationsRepositoryProvider)
        .assign(serviceId: id, assignments: assignments);
    await load();
  }

  Future<void> addNote(String id, String message) async {
    await ref
        .read(operationsRepositoryProvider)
        .addUpdate(serviceId: id, type: 'note', message: message);
    await load();
  }

  Future<void> toggleStep(String id, String stepId, bool done) async {
    await ref
        .read(operationsRepositoryProvider)
        .addUpdate(
          serviceId: id,
          type: 'step_update',
          stepId: stepId,
          stepDone: done,
        );
    await load();
  }

  Future<void> createWarranty(
    String id, {
    String? title,
    String? description,
  }) async {
    await ref
        .read(operationsRepositoryProvider)
        .createWarranty(serviceId: id, title: title, description: description);
    await load();
  }

  Future<void> uploadEvidence(String id, PlatformFile file) async {
    await ref
        .read(operationsRepositoryProvider)
        .uploadEvidence(serviceId: id, file: file);
    await load();
  }

  Future<void> deleteService(String id) async {
    await ref.read(operationsRepositoryProvider).deleteService(id);
    await load();
  }

  Future<List<ServiceModel>> customerServices(String customerId) {
    return ref.read(operationsRepositoryProvider).customerServices(customerId);
  }

  Future<List<ClienteModel>> searchClients(String query) {
    return ref.read(operationsRepositoryProvider).searchClients(query);
  }

  Future<ClienteModel> createQuickClient({
    required String nombre,
    required String telefono,
  }) {
    return ref
        .read(operationsRepositoryProvider)
        .createQuickClient(nombre: nombre, telefono: telefono);
  }
}
