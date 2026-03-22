import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/user_model.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../data/service_orders_api.dart';
import 'service_orders_list_controller.dart';
import '../data/upload_repository.dart';
import '../service_order_models.dart';
import '../../../features/user/data/users_repository.dart';

class ServiceOrderDetailState {
  final bool loading;
  final bool working;
  final String? error;
  final String? actionError;
  final ServiceOrderModel? order;
  final ClienteModel? client;
  final Map<String, UserModel> usersById;

  const ServiceOrderDetailState({
    this.loading = false,
    this.working = false,
    this.error,
    this.actionError,
    this.order,
    this.client,
    this.usersById = const {},
  });

  ServiceOrderDetailState copyWith({
    bool? loading,
    bool? working,
    String? error,
    String? actionError,
    ServiceOrderModel? order,
    ClienteModel? client,
    Map<String, UserModel>? usersById,
    bool clearError = false,
    bool clearActionError = false,
  }) {
    return ServiceOrderDetailState(
      loading: loading ?? this.loading,
      working: working ?? this.working,
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      order: order ?? this.order,
      client: client ?? this.client,
      usersById: usersById ?? this.usersById,
    );
  }
}

final serviceOrderDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ServiceOrderDetailController, ServiceOrderDetailState, String>(
  (ref, orderId) {
    return ServiceOrderDetailController(ref, orderId)..load();
  },
);

class ServiceOrderDetailController extends StateNotifier<ServiceOrderDetailState> {
  ServiceOrderDetailController(this.ref, this.orderId)
      : super(const ServiceOrderDetailState());

  final Ref ref;
  final String orderId;

  Future<void> load() async {
    state = state.copyWith(
      loading: state.order == null,
      working: false,
      clearError: true,
      clearActionError: true,
    );
    try {
      final order = await ref.read(serviceOrdersApiProvider).getOrder(orderId);
      final futures = <Future<dynamic>>[
        ref
            .read(clientesRepositoryProvider)
            .getClientById(ownerId: '', id: order.clientId),
        ref.read(usersRepositoryProvider).getAllUsers(),
      ];
      final results = await Future.wait<dynamic>(futures);
      final client = results[0] as ClienteModel;
      final users = results[1] as List<UserModel>;
      state = state.copyWith(
        loading: false,
        order: order,
        client: client,
        usersById: {for (final user in users) user.id: user},
      );
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo cargar la orden';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> refresh() => load();

  Future<void> updateStatus(ServiceOrderStatus status) async {
    final currentOrder = state.order;
    if (currentOrder == null) return;

    state = state.copyWith(working: true, clearActionError: true);
    final previousOrder = currentOrder;
    final optimisticOrder = currentOrder.copyWith(status: status);
    state = state.copyWith(order: optimisticOrder);
    ref
        .read(serviceOrdersListControllerProvider.notifier)
        .replaceOrderStatus(orderId: orderId, status: status);

    try {
      final updated = await ref.read(serviceOrdersApiProvider).updateStatus(orderId, status);
      state = state.copyWith(working: false, order: updated);
      ref.read(serviceOrdersListControllerProvider.notifier).upsertOrder(updated);
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo actualizar el estado';
      state = state.copyWith(
        working: false,
        order: previousOrder,
        actionError: message,
      );
      ref
          .read(serviceOrdersListControllerProvider.notifier)
          .upsertOrder(previousOrder);
      rethrow;
    }
  }

  Future<void> addTextEvidence(String content) async {
    await _addEvidence(
      CreateServiceOrderEvidenceRequest(
        type: ServiceEvidenceType.evidenciaTexto,
        content: content,
      ),
    );
  }

  Future<void> addImageEvidence({
    required List<int> bytes,
    required String fileName,
    String? path,
  }) async {
    state = state.copyWith(working: true, clearActionError: true);
    try {
      final uploaded = await ref.read(uploadRepositoryProvider).uploadImage(
            bytes: bytes,
            path: path,
            fileName: fileName,
          );
      await ref.read(serviceOrdersApiProvider).addEvidence(
            orderId,
            CreateServiceOrderEvidenceRequest(
              type: ServiceEvidenceType.evidenciaImagen,
              content: uploaded.url,
            ),
          );
      await load();
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo subir la imagen';
      state = state.copyWith(working: false, actionError: message);
      rethrow;
    }
  }

  Future<void> addVideoEvidence({
    required String fileName,
    List<int>? bytes,
    String? path,
  }) async {
    state = state.copyWith(working: true, clearActionError: true);
    try {
      final uploaded = await ref.read(uploadRepositoryProvider).uploadVideo(
            fileName: fileName,
            bytes: bytes,
            path: path,
          );
      await ref.read(serviceOrdersApiProvider).addEvidence(
            orderId,
            CreateServiceOrderEvidenceRequest(
              type: ServiceEvidenceType.evidenciaVideo,
              content: uploaded.url,
            ),
          );
      await load();
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo subir el video';
      state = state.copyWith(working: false, actionError: message);
      rethrow;
    }
  }

  Future<void> addReport(String report) async {
    state = state.copyWith(working: true, clearActionError: true);
    try {
      await ref.read(serviceOrdersApiProvider).addReport(orderId, report);
      await load();
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo guardar el reporte';
      state = state.copyWith(working: false, actionError: message);
      rethrow;
    }
  }

  Future<void> _addEvidence(CreateServiceOrderEvidenceRequest request) async {
    state = state.copyWith(working: true, clearActionError: true);
    try {
      await ref.read(serviceOrdersApiProvider).addEvidence(orderId, request);
      await load();
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo guardar la evidencia';
      state = state.copyWith(working: false, actionError: message);
      rethrow;
    }
  }
}