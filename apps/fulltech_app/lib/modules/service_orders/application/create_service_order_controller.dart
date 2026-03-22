import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/user_model.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../../cotizaciones/cotizacion_models.dart';
import '../../cotizaciones/data/cotizaciones_repository.dart';
import '../../../features/user/data/users_repository.dart';
import '../data/service_orders_api.dart';
import '../service_order_models.dart';

class CreateServiceOrderState {
  final bool loading;
  final bool submitting;
  final bool initialized;
  final String? error;
  final String? actionError;
  final List<ClienteModel> clients;
  final List<CotizacionModel> quotations;
  final List<UserModel> technicians;
  final ClienteModel? selectedClient;
  final CotizacionModel? selectedQuotation;
  final UserModel? selectedTechnician;
  final ServiceOrderCategory category;
  final ServiceOrderType? serviceType;
  final ServiceOrderModel? cloneSource;

  const CreateServiceOrderState({
    this.loading = false,
    this.submitting = false,
    this.initialized = false,
    this.error,
    this.actionError,
    this.clients = const [],
    this.quotations = const [],
    this.technicians = const [],
    this.selectedClient,
    this.selectedQuotation,
    this.selectedTechnician,
    this.category = ServiceOrderCategory.camara,
    this.serviceType,
    this.cloneSource,
  });

  bool get isCloneMode => cloneSource != null;

  CreateServiceOrderState copyWith({
    bool? loading,
    bool? submitting,
    bool? initialized,
    String? error,
    String? actionError,
    List<ClienteModel>? clients,
    List<CotizacionModel>? quotations,
    List<UserModel>? technicians,
    ClienteModel? selectedClient,
    CotizacionModel? selectedQuotation,
    UserModel? selectedTechnician,
    ServiceOrderCategory? category,
    ServiceOrderType? serviceType,
    ServiceOrderModel? cloneSource,
    bool clearError = false,
    bool clearActionError = false,
    bool clearSelectedQuotation = false,
    bool clearSelectedTechnician = false,
  }) {
    return CreateServiceOrderState(
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      initialized: initialized ?? this.initialized,
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      clients: clients ?? this.clients,
      quotations: quotations ?? this.quotations,
      technicians: technicians ?? this.technicians,
      selectedClient: selectedClient ?? this.selectedClient,
      selectedQuotation: clearSelectedQuotation
          ? null
          : (selectedQuotation ?? this.selectedQuotation),
      selectedTechnician: clearSelectedTechnician
          ? null
          : (selectedTechnician ?? this.selectedTechnician),
      category: category ?? this.category,
      serviceType: serviceType ?? this.serviceType,
      cloneSource: cloneSource ?? this.cloneSource,
    );
  }
}

final createServiceOrderControllerProvider = StateNotifierProvider.autoDispose
    .family<CreateServiceOrderController, CreateServiceOrderState,
        ServiceOrderCreateArgs?>((ref, args) {
  return CreateServiceOrderController(ref, args)..load();
});

class CreateServiceOrderController extends StateNotifier<CreateServiceOrderState> {
  CreateServiceOrderController(this.ref, this.args)
      : super(
          CreateServiceOrderState(
            cloneSource: args?.cloneSource,
            category:
                args?.cloneSource?.category ?? ServiceOrderCategory.camara,
          ),
        );

  final Ref ref;
  final ServiceOrderCreateArgs? args;

  String get _ownerId => ref.read(authStateProvider).user?.id ?? '';

  Future<void> load() async {
    if (state.initialized || state.loading) return;
    state = state.copyWith(loading: true, clearError: true, clearActionError: true);
    try {
      final results = await Future.wait<dynamic>([
        ref.read(clientesRepositoryProvider).listClients(
              ownerId: _ownerId,
              pageSize: 200,
            ),
        ref.read(usersRepositoryProvider).getAllUsers(),
      ]);
      final clients = results[0] as List<ClienteModel>;
      final users = results[1] as List<UserModel>;
      final technicians = users
          .where((user) => user.appRole == AppRole.tecnico)
          .toList(growable: false);
      final cloneSource = args?.cloneSource;
      final selectedClient = cloneSource == null
          ? null
          : clients.where((item) => item.id == cloneSource.clientId).firstWhere(
                (item) => true,
                orElse: () => ClienteModel(
                  id: cloneSource.clientId,
                  ownerId: _ownerId,
                  nombre: 'Cliente vinculado',
                  telefono: '',
                ),
              );
      final selectedTechnician = cloneSource?.assignedToId == null
          ? null
          : technicians.where((item) => item.id == cloneSource!.assignedToId).firstWhere(
                (item) => true,
                orElse: () => UserModel(
                  id: cloneSource!.assignedToId!,
                  email: '',
                  nombreCompleto: 'Técnico asignado',
                  telefono: '',
                  role: 'TECNICO',
                ),
              );
      state = state.copyWith(
        loading: false,
        initialized: true,
        clients: clients,
        technicians: technicians,
        selectedClient: selectedClient,
        selectedTechnician: selectedTechnician,
        serviceType: cloneSource?.serviceType,
      );
      if (selectedClient != null) {
        await selectClient(selectedClient, preserveQuotationId: cloneSource?.quotationId);
      }
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo preparar el formulario';
      state = state.copyWith(loading: false, initialized: true, error: message);
    }
  }

  Future<void> selectClient(
    ClienteModel client, {
    String? preserveQuotationId,
  }) async {
    state = state.copyWith(
      selectedClient: client,
      quotations: const [],
      clearSelectedQuotation: true,
      clearError: true,
      clearActionError: true,
      loading: true,
    );
    if (client.telefono.trim().isEmpty) {
      state = state.copyWith(
        loading: false,
        quotations: const [],
        actionError:
            'El cliente no tiene teléfono. No se pueden cargar cotizaciones vinculadas.',
      );
      return;
    }

    try {
      final quotations = await ref.read(cotizacionesRepositoryProvider).list(
            customerPhone: client.telefono.trim(),
          );
      CotizacionModel? selectedQuotation;
      if ((preserveQuotationId ?? '').trim().isNotEmpty) {
        for (final quotation in quotations) {
          if (quotation.id == preserveQuotationId) {
            selectedQuotation = quotation;
            break;
          }
        }
      }
      state = state.copyWith(
        loading: false,
        quotations: quotations,
        selectedQuotation: selectedQuotation,
      );
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudieron cargar las cotizaciones';
      state = state.copyWith(loading: false, actionError: message);
    }
  }

  void selectQuotation(CotizacionModel? quotation) {
    state = state.copyWith(
      selectedQuotation: quotation,
      clearActionError: true,
    );
  }

  void selectTechnician(UserModel? user) {
    state = state.copyWith(
      selectedTechnician: user,
      clearActionError: true,
    );
  }

  void setCategory(ServiceOrderCategory category) {
    if (state.isCloneMode) return;
    state = state.copyWith(category: category, clearActionError: true);
  }

  void setServiceType(ServiceOrderType? serviceType) {
    state = state.copyWith(serviceType: serviceType, clearActionError: true);
  }

  Future<ServiceOrderModel> submit({
    required String technicalNote,
    required String extraRequirements,
  }) async {
    final client = state.selectedClient;
    final quotation = state.selectedQuotation;
    final serviceType = state.serviceType;
    if (client == null) {
      throw ApiException('Debes seleccionar un cliente');
    }
    if (quotation == null && !state.isCloneMode) {
      throw ApiException('Debes seleccionar una cotización');
    }
    if (serviceType == null) {
      throw ApiException('Debes seleccionar el tipo de servicio');
    }

    state = state.copyWith(submitting: true, clearActionError: true);
    try {
      final result = state.isCloneMode
          ? await ref.read(serviceOrdersApiProvider).cloneOrder(
                state.cloneSource!.id,
                CloneServiceOrderRequest(
                  serviceType: serviceType,
                  technicalNote: technicalNote,
                  extraRequirements: extraRequirements,
                  assignedToId: state.selectedTechnician?.id,
                ),
              )
          : await ref.read(serviceOrdersApiProvider).createOrder(
                CreateServiceOrderRequest(
                  clientId: client.id,
                  quotationId: quotation!.id,
                  category: state.category,
                  serviceType: serviceType,
                  technicalNote: technicalNote,
                  extraRequirements: extraRequirements,
                  assignedToId: state.selectedTechnician?.id,
                ),
              );
      state = state.copyWith(submitting: false);
      return result;
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo guardar la orden';
      state = state.copyWith(submitting: false, actionError: message);
      rethrow;
    }
  }
}