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
  final bool refreshing;
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
    this.refreshing = false,
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
    bool? refreshing,
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
      refreshing: refreshing ?? this.refreshing,
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

final ordersProvider = Provider<List<ServiceModel>>((ref) {
  return ref.watch(
    operationsControllerProvider.select((state) => state.services),
  );
});

final ordersLoadingProvider = Provider<bool>((ref) {
  return ref.watch(
    operationsControllerProvider.select(
      (state) => state.loading || state.refreshing,
    ),
  );
});

final ordersErrorProvider = Provider<String?>((ref) {
  return ref.watch(operationsControllerProvider.select((state) => state.error));
});

final serviceProvider = FutureProvider.family<ServiceModel, String>((
  ref,
  serviceId,
) async {
  final services = ref.watch(ordersProvider);

  for (final service in services) {
    if (service.id == serviceId) return service;
  }

  return ref.read(operationsControllerProvider.notifier).getOne(serviceId);
});

class OperationsController extends StateNotifier<OperationsState> {
  final Ref ref;
  int _loadSeq = 0;
  final Map<String, DateTime> _detailPrefetchAt = <String, DateTime>{};

  static const int _detailPrefetchLimit = 6;
  static const Duration _detailPrefetchTtl = Duration(minutes: 2);

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
        refreshing: hasCached || state.services.isNotEmpty,
        clearError: true,
        services: cachedPage?.items ?? state.services,
        dashboard: cachedDashboard ?? state.dashboard,
      );
      _prefetchLikelyDetails(cachedItems);

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
            refreshing: false,
            services: page.items,
            dashboard: dashboard,
          );
          _prefetchLikelyDetails(page.items);
        } catch (e) {
          if (!mounted || seq != _loadSeq) return;
          state = state.copyWith(
            loading: false,
            refreshing: false,
            error: e is ApiException
                ? e.message
                : 'No se pudo cargar operaciones',
          );
        }
      }());
    } catch (e) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: e is ApiException ? e.message : 'No se pudo cargar operaciones',
      );
    }
  }

  Future<void> refresh() => load();

  void applyRealtimeService(ServiceModel service) {
    final before = state.services;
    final index = before.indexWhere((s) => s.id == service.id);
    final matches = _matchesCurrentFilters(service);

    if (!matches) {
      if (index < 0) return;
      final next = [...before]..removeAt(index);
      state = state.copyWith(services: next);
      return;
    }

    final next = [...before];
    if (index >= 0) {
      next[index] = service;
    } else {
      next.insert(0, service);
    }
    next.sort(_sortServicesForRealtime);
    state = state.copyWith(services: next);
    _prefetchLikelyDetails([service]);
  }

  void _prefetchLikelyDetails(List<ServiceModel> services) {
    if (services.isEmpty) return;

    var queued = 0;
    for (final service in services) {
      final id = service.id.trim();
      if (id.isEmpty) continue;
      unawaited(prefetchServiceBundle(id));
      queued++;
      if (queued >= _detailPrefetchLimit) break;
    }
  }

  Future<void> prefetchServiceBundle(
    String serviceId, {
    bool force = false,
  }) async {
    final id = serviceId.trim();
    if (id.isEmpty) return;

    final now = DateTime.now();
    final last = _detailPrefetchAt[id];
    if (!force && last != null && now.difference(last) < _detailPrefetchTtl) {
      return;
    }
    _detailPrefetchAt[id] = now;

    final auth = ref.read(authStateProvider);
    final cacheScope = (auth.user?.id ?? '').trim();
    if (cacheScope.isEmpty) return;

    final technicianId =
        (auth.user?.role ?? '').trim().toLowerCase() == 'tecnico'
        ? cacheScope
        : null;

    await ref
        .read(operationsRepositoryProvider)
        .warmServiceDetailCaches(
          cacheScope: cacheScope,
          serviceId: id,
          technicianId: technicianId,
        );
  }

  bool _matchesCurrentFilters(ServiceModel service) {
    String norm(String? value) => (value ?? '').trim().toLowerCase();

    bool same(String? left, String? right) {
      final a = norm(left);
      final b = norm(right);
      if (a.isEmpty || b.isEmpty) return false;
      return a == b;
    }

    final statusFilter = norm(state.statusFilter);
    if (statusFilter.isNotEmpty) {
      final candidates = <String>{
        norm(effectiveServiceStatusKey(service)),
        norm(effectiveServicePhaseKey(service)),
        norm(service.status),
        norm(service.phase),
      }..remove('');
      if (!candidates.contains(statusFilter)) return false;
    }

    if (state.typeFilter != null &&
        !same(service.serviceType, state.typeFilter)) {
      return false;
    }

    if (state.orderTypeFilter != null &&
        !same(service.orderType, state.orderTypeFilter)) {
      return false;
    }

    final orderStateFilter = norm(state.orderStateFilter);
    if (orderStateFilter.isNotEmpty) {
      final candidates = <String>{
        norm(effectiveServiceStatusKey(service)),
        norm(service.orderState),
        norm(service.status),
      }..remove('');
      if (!candidates.contains(orderStateFilter)) return false;
    }

    final technicianFilter = norm(state.technicianIdFilter);
    if (technicianFilter.isNotEmpty) {
      final assignedIds = <String>{
        norm(service.technicianId),
        ...service.assignments.map((a) => norm(a.userId)),
      }..remove('');
      if (!assignedIds.contains(technicianFilter)) return false;
    }

    if (state.priorityFilter != null &&
        service.priority != state.priorityFilter) {
      return false;
    }

    final customerFilter = norm(state.customerIdFilter);
    if (customerFilter.isNotEmpty &&
        !same(service.customerId, customerFilter)) {
      return false;
    }

    final query = norm(state.search);
    if (query.isNotEmpty) {
      final haystack = [
        service.orderLabel,
        service.title,
        service.description,
        service.customerName,
        service.customerPhone,
        service.customerAddress,
        service.category,
        service.categoryName ?? '',
        effectiveServicePhaseKey(service),
        service.serviceType,
        service.orderType,
        effectiveServiceStatusKey(service),
        service.phase,
        service.status,
      ].map(norm).join(' ');
      if (!haystack.contains(query)) return false;
    }

    final pivot =
        service.scheduledStart ?? service.createdAt ?? service.completedAt;
    final from = state.from;
    if (from != null && pivot != null && pivot.isBefore(from)) return false;
    final to = state.to;
    if (to != null && pivot != null && pivot.isAfter(to)) return false;

    return true;
  }

  int _sortServicesForRealtime(ServiceModel a, ServiceModel b) {
    final ad =
        a.createdAt ??
        a.scheduledStart ??
        a.completedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bd =
        b.createdAt ??
        b.scheduledStart ??
        b.completedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return bd.compareTo(ad);
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

  Future<ServiceModel> getOne(String id, {bool preferCache = true}) async {
    if (preferCache) {
      for (final service in state.services) {
        if (service.id == id) return service;
      }
    }

    final repo = ref.read(operationsRepositoryProvider);
    final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();

    if (cacheScope.isEmpty) {
      return repo.getService(id);
    }

    if (preferCache) {
      final cached = await repo.getCachedService(
        cacheScope: cacheScope,
        id: id,
      );
      if (cached != null) {
        unawaited(
          repo.getServiceAndCache(cacheScope: cacheScope, id: id, silent: true),
        );
        return cached;
      }
    }

    return repo.getServiceAndCache(
      cacheScope: cacheScope,
      id: id,
      silent: true,
    );
  }

  void _invalidateServiceDetail(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    ref.invalidate(serviceProvider(trimmed));
  }

  void _commitServiceSnapshot(ServiceModel service) {
    applyRealtimeService(service);
    _invalidateServiceDetail(service.id);
  }

  void _scheduleGlobalRefresh() {
    unawaited(load());
  }

  String? _normalizeAdminStatus(String? raw) {
    final value = normalizeOperationsKey(raw ?? '');
    if (value.isEmpty) return null;

    switch (value) {
      case 'pendiente':
      case 'confirmada':
      case 'asignada':
      case 'en_camino':
      case 'en_proceso':
      case 'finalizada':
      case 'reagendada':
      case 'cancelada':
      case 'cerrada':
        return value;
      case 'pending':
      case 'reserved':
      case 'survey':
      case 'scheduled':
        return 'pendiente';
      case 'confirmed':
        return 'confirmada';
      case 'assigned':
        return 'asignada';
      case 'in_progress':
      case 'warranty':
        return 'en_proceso';
      case 'finalized':
      case 'completed':
        return 'finalizada';
      case 'closed':
        return 'cerrada';
      case 'cancelled':
        return 'cancelada';
      case 'rescheduled':
        return 'reagendada';
      default:
        return null;
    }
  }

  String? _legacyOrderStateForAdminStatus(String? raw) {
    final value = _normalizeAdminStatus(raw);
    switch (value) {
      case 'pendiente':
        return 'pending';
      case 'confirmada':
        return 'confirmed';
      case 'asignada':
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

  Future<ServiceModel> updateService({
    required String serviceId,
    String? phase,
    DateTime? scheduledAt,
    String? note,
    String? status,
    String? serviceType,
    String? categoryId,
    String? category,
    int? priority,
    String? title,
    String? description,
    double? quotedAmount,
    double? depositAmount,
    String? addressSnapshot,
    String? warrantyParentServiceId,
    String? surveyResult,
    String? materialsUsed,
    double? finalCost,
    String? orderType,
    String? orderState,
    String? adminPhase,
    String? adminStatus,
    String? technicianId,
    List<String>? tags,
  }) async {
    final updated = await ref
        .read(operationsRepositoryProvider)
        .updateService(
          serviceId: serviceId,
          phase: phase,
          scheduledAt: scheduledAt,
          note: note,
          status: status,
          serviceType: serviceType,
          categoryId: categoryId,
          category: category,
          priority: priority,
          title: title,
          description: description,
          quotedAmount: quotedAmount,
          depositAmount: depositAmount,
          addressSnapshot: addressSnapshot,
          warrantyParentServiceId: warrantyParentServiceId,
          surveyResult: surveyResult,
          materialsUsed: materialsUsed,
          finalCost: finalCost,
          orderType: orderType,
          orderState: orderState,
          adminPhase: adminPhase,
          adminStatus: adminStatus,
          technicianId: technicianId,
          tags: tags,
        );
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
    return updated;
  }

  Future<ServiceModel> createReservation({
    required String customerId,
    required String serviceType,
    String? categoryId,
    required int priority,
    required String title,
    required String description,
    String? category,
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
    final effectiveAdminStatus =
        adminStatus ?? (hasTech ? 'asignada' : 'pendiente');
    final legacyOrderState = legacyOrderStateForAdminStatus(
      effectiveAdminStatus,
    );

    final normalizedType = (orderType ?? 'reserva').trim().toLowerCase();
    final effectiveAdminPhase = normalizedType == 'reserva'
        ? 'reserva'
        : 'programacion';

    final service = await ref
        .read(operationsRepositoryProvider)
        .createService(
          customerId: customerId,
          serviceType: serviceType,
          categoryId: categoryId,
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
    _invalidateServiceDetail(service.id);
    await load();
    return service;
  }

  Future<void> changeStatus(String id, String status, {String? message}) async {
    final nextAdminStatus = _normalizeAdminStatus(status);
    final nextOrderState = _legacyOrderStateForAdminStatus(status);
    final updated = await ref
        .read(operationsRepositoryProvider)
        .updateService(
          serviceId: id,
          adminStatus: nextAdminStatus ?? status,
          orderState: nextOrderState,
        );
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
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
    final nextAdminStatus = _normalizeAdminStatus(next) ?? next;
    final nextOrderState = _legacyOrderStateForAdminStatus(next);

    if (index < 0) {
      final updated = await ref
          .read(operationsRepositoryProvider)
          .updateService(
            serviceId: id,
            adminStatus: nextAdminStatus,
            orderState: nextOrderState,
          );
      _commitServiceSnapshot(updated);
      _scheduleGlobalRefresh();
      return;
    }

    final current = before[index];
    if (effectiveServiceStatusKey(current) == nextAdminStatus) return;

    final optimistic = current.copyWith(
      adminStatus: nextAdminStatus,
      orderState: nextOrderState ?? current.orderState,
    );
    final optimisticList = [...before];
    optimisticList[index] = optimistic;
    state = state.copyWith(services: optimisticList);

    try {
      final updated = await ref
          .read(operationsRepositoryProvider)
          .updateService(
            serviceId: id,
            adminStatus: nextAdminStatus,
            orderState: nextOrderState,
          );
      _commitServiceSnapshot(updated);
      _scheduleGlobalRefresh();
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
      final updated = await ref
          .read(operationsRepositoryProvider)
          .updateService(serviceId: id, adminPhase: next);
      _commitServiceSnapshot(updated);
      _scheduleGlobalRefresh();
      return updated;
    }

    final current = before[index];
    if ((current.adminPhase ?? '').trim().toLowerCase() == next) return current;

    final optimistic = current.copyWith(adminPhase: next);
    final optimisticList = [...before];
    optimisticList[index] = optimistic;
    state = state.copyWith(services: optimisticList);

    try {
      final updated = await ref
          .read(operationsRepositoryProvider)
          .updateService(serviceId: id, adminPhase: next);
      _commitServiceSnapshot(updated);
      _scheduleGlobalRefresh();
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
          .updateService(
            serviceId: id,
            phase: next,
            scheduledAt: scheduledAt,
            note: note,
          );
      _commitServiceSnapshot(updated.copyWith(scheduledStart: scheduledAt));
      _scheduleGlobalRefresh();
      return updated;
    }

    final current = before[index];
    if (current.phase.trim().toLowerCase() == next) return current;

    final optimistic = current.copyWith(
      phase: next,
      currentPhase: next,
      orderType: next,
      scheduledStart: scheduledAt,
    );
    final optimisticList = [...before];
    optimisticList[index] = optimistic;
    state = state.copyWith(services: optimisticList);

    try {
      final updated = await ref
          .read(operationsRepositoryProvider)
          .updateService(
            serviceId: id,
            phase: next,
            scheduledAt: scheduledAt,
            note: note,
          );
      _commitServiceSnapshot(updated.copyWith(scheduledStart: scheduledAt));
      _scheduleGlobalRefresh();
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
    final updated = await ref
        .read(operationsRepositoryProvider)
        .schedule(serviceId: id, start: start, end: end, message: message);
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
  }

  Future<void> assign(String id, List<Map<String, String>> assignments) async {
    final updated = await ref
        .read(operationsRepositoryProvider)
        .assign(serviceId: id, assignments: assignments);
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
  }

  Future<void> addNote(String id, String message) async {
    await ref
        .read(operationsRepositoryProvider)
        .addUpdate(serviceId: id, type: 'note', message: message);
    final updated = await getOne(id, preferCache: false);
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
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
    final updated = await getOne(id, preferCache: false);
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
  }

  Future<void> createWarranty(
    String id, {
    String? title,
    String? description,
  }) async {
    final updated = await ref
        .read(operationsRepositoryProvider)
        .createWarranty(serviceId: id, title: title, description: description);
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
  }

  Future<void> uploadEvidence(String id, PlatformFile file) async {
    await ref
        .read(operationsRepositoryProvider)
        .uploadEvidence(serviceId: id, file: file);
    final updated = await getOne(id, preferCache: false);
    _commitServiceSnapshot(updated);
    _scheduleGlobalRefresh();
  }

  Future<void> deleteService(String id) async {
    await ref.read(operationsRepositoryProvider).deleteService(id);
    _invalidateServiceDetail(id);
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
