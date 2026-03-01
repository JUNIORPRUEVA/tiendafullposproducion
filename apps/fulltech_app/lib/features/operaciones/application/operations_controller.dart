import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

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
    return OperationsState(
      dashboard: OperationsDashboardModel.empty(),
      from: start,
      to: start.add(const Duration(days: 7)),
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
      orderTypeFilter: clearOrderType ? null : (orderTypeFilter ?? this.orderTypeFilter),
      orderStateFilter: clearOrderState ? null : (orderStateFilter ?? this.orderStateFilter),
      technicianIdFilter: clearTechnician ? null : (technicianIdFilter ?? this.technicianIdFilter),
      priorityFilter: clearPriority ? null : (priorityFilter ?? this.priorityFilter),
      customerIdFilter: clearCustomer ? null : (customerIdFilter ?? this.customerIdFilter),
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

  OperationsController(this.ref) : super(OperationsState.initial()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(operationsRepositoryProvider);
      final results = await Future.wait([
        repo.listServices(
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
        repo.dashboard(from: state.from, to: state.to),
      ]);

      final page = results[0] as ServicesPageModel;
      final dashboard = results[1] as OperationsDashboardModel;

      state = state.copyWith(
        loading: false,
        services: page.items,
        dashboard: dashboard,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: e is ApiException ? e.message : 'No se pudo cargar operaciones',
      );
    }
  }

  Future<void> refresh() => load();

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

  Future<ServiceModel> getOne(String id) {
    return ref.read(operationsRepositoryProvider).getService(id);
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
          orderState: orderState,
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

  Future<void> schedule(String id, DateTime start, DateTime end,
      {String? message}) async {
    await ref.read(operationsRepositoryProvider).schedule(
          serviceId: id,
          start: start,
          end: end,
          message: message,
        );
    await load();
  }

  Future<void> assign(String id, List<Map<String, String>> assignments) async {
    await ref
        .read(operationsRepositoryProvider)
        .assign(serviceId: id, assignments: assignments);
    await load();
  }

  Future<void> addNote(String id, String message) async {
    await ref.read(operationsRepositoryProvider).addUpdate(
          serviceId: id,
          type: 'note',
          message: message,
        );
    await load();
  }

  Future<void> toggleStep(String id, String stepId, bool done) async {
    await ref.read(operationsRepositoryProvider).addUpdate(
          serviceId: id,
          type: 'step_update',
          stepId: stepId,
          stepDone: done,
        );
    await load();
  }

  Future<void> createWarranty(String id, {String? title, String? description}) async {
    await ref.read(operationsRepositoryProvider).createWarranty(
          serviceId: id,
          title: title,
          description: description,
        );
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
    return ref.read(operationsRepositoryProvider).createQuickClient(
          nombre: nombre,
          telefono: telefono,
        );
  }
}
