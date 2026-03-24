import 'dart:async';
import 'dart:typed_data';

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
  Future<void> _uploadQueue = Future<void>.value();

  String _friendlyOrderMessage(
    Object error, {
    required String fallback,
    required String forbiddenMessage,
  }) {
    if (error is ApiException) {
      if (error.type == ApiErrorType.forbidden || error.code == 403) {
        return forbiddenMessage;
      }
      return error.message;
    }
    return fallback;
  }

  Future<void> load() async {
    state = state.copyWith(
      loading: state.order == null,
      working: false,
      clearError: true,
      clearActionError: true,
    );
    try {
      final order = await ref.read(serviceOrdersApiProvider).getOrder(orderId);
      final usersFuture = ref
          .read(usersRepositoryProvider)
          .getAllUsers()
          .catchError((_) => <UserModel>[]);
      final fallbackClientFuture = order.client != null
          ? Future<ClienteModel?>.value(order.client)
          : ref
              .read(clientesRepositoryProvider)
              .getClientById(ownerId: '', id: order.clientId)
              .then<ClienteModel?>((value) => value)
              .catchError((_) => null);
      final results = await Future.wait<dynamic>([
        fallbackClientFuture,
        usersFuture,
      ]);
      final client = results[0] as ClienteModel?;
      final users = results[1] as List<UserModel>;
      state = state.copyWith(
        loading: false,
        order: order,
        client: client,
        usersById: {for (final user in users) user.id: user},
      );
    } catch (error) {
      final message = _friendlyOrderMessage(
        error,
        fallback: 'No se pudo cargar la orden',
        forbiddenMessage: 'No tienes permiso para ver esta orden',
      );
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> refresh() => load();

  Future<void> updateOperationalDetails({
    required String? technicalNote,
    required String? extraRequirements,
  }) async {
    final currentOrder = state.order;
    if (currentOrder == null) return;

    state = state.copyWith(working: true, clearActionError: true);
    try {
      final updated = await ref.read(serviceOrdersApiProvider).updateOrder(
        orderId,
        UpdateServiceOrderRequest(
          clientId: currentOrder.clientId,
          quotationId: currentOrder.quotationId ?? '',
          category: currentOrder.category,
          serviceType: currentOrder.serviceType,
          assignedToId: currentOrder.assignedToId,
          technicalNote: technicalNote,
          extraRequirements: extraRequirements,
        ),
      );
      state = state.copyWith(working: false, order: updated);
      ref.read(serviceOrdersListControllerProvider.notifier).upsertOrder(updated);
    } catch (error) {
      final message = _friendlyOrderMessage(
        error,
        fallback: 'No se pudieron guardar los cambios operativos',
        forbiddenMessage:
            'No tienes permiso para actualizar las notas operativas de esta orden',
      );
      state = state.copyWith(working: false, actionError: message);
      rethrow;
    }
  }

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
      final message = _friendlyOrderMessage(
        error,
        fallback: 'No se pudo actualizar el estado',
        forbiddenMessage: 'No tienes permiso para cambiar el estado de esta orden',
      );
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
    final order = state.order;
    if (order == null) {
      throw ApiException('No hay una orden cargada para adjuntar evidencias');
    }

    state = state.copyWith(clearActionError: true);
    final optimistic = _buildOptimisticEvidence(
      type: ServiceEvidenceType.evidenciaImagen,
      fileName: fileName,
      path: path,
      bytes: bytes,
    );
    _upsertOptimisticEvidence(optimistic);

    unawaited(
      _enqueueUpload(() async {
        try {
          final uploaded = await ref.read(uploadRepositoryProvider).uploadImage(
                bytes: bytes,
                path: path,
                fileName: fileName,
              );
          final saved = await ref.read(serviceOrdersApiProvider).addEvidence(
                orderId,
                CreateServiceOrderEvidenceRequest(
                  type: ServiceEvidenceType.evidenciaImagen,
                  content: uploaded.url,
                ),
              );
          _replaceEvidence(temporaryId: optimistic.id, persisted: saved);
        } catch (error) {
          final message = error is ApiException
              ? error.message
              : 'No se pudo subir la imagen';
          _markEvidenceUploadFailed(optimistic.id, message);
        }
      }),
    );
  }

  Future<void> addVideoEvidence({
    required String fileName,
    List<int>? bytes,
    String? path,
  }) async {
    final order = state.order;
    if (order == null) {
      throw ApiException('No hay una orden cargada para adjuntar evidencias');
    }

    state = state.copyWith(clearActionError: true);
    final optimistic = _buildOptimisticEvidence(
      type: ServiceEvidenceType.evidenciaVideo,
      fileName: fileName,
      path: path,
      bytes: bytes,
    );
    _upsertOptimisticEvidence(optimistic);

    unawaited(
      _enqueueUpload(() async {
        try {
          final uploaded = await ref.read(uploadRepositoryProvider).uploadVideo(
                fileName: fileName,
                bytes: bytes,
                path: path,
              );
          final saved = await ref.read(serviceOrdersApiProvider).addEvidence(
                orderId,
                CreateServiceOrderEvidenceRequest(
                  type: ServiceEvidenceType.evidenciaVideo,
                  content: uploaded.url,
                ),
              );
          _replaceEvidence(temporaryId: optimistic.id, persisted: saved);
        } catch (error) {
          final message = error is ApiException
              ? error.message
              : 'No se pudo subir el video';
          _markEvidenceUploadFailed(optimistic.id, message);
        }
      }),
    );
  }

  Future<void> addReport(ServiceReportType type, String report) async {
    state = state.copyWith(working: true, clearActionError: true);
    try {
      await ref.read(serviceOrdersApiProvider).addReport(orderId, type, report);
      await load();
    } catch (error) {
      final message = _friendlyOrderMessage(
        error,
        fallback: 'No se pudo guardar el reporte',
        forbiddenMessage: 'No tienes permiso para agregar reportes en esta orden',
      );
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
      final message = _friendlyOrderMessage(
        error,
        fallback: 'No se pudo guardar la evidencia',
        forbiddenMessage: 'No tienes permiso para agregar evidencias en esta orden',
      );
      state = state.copyWith(working: false, actionError: message);
      rethrow;
    }
  }

  Future<void> _enqueueUpload(Future<void> Function() task) {
    _uploadQueue = _uploadQueue
        .then((_) => task())
        .catchError((_) {});
    return _uploadQueue;
  }

  ServiceOrderEvidenceModel _buildOptimisticEvidence({
    required ServiceEvidenceType type,
    required String fileName,
    required String? path,
    required List<int>? bytes,
  }) {
    return ServiceOrderEvidenceModel(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      serviceOrderId: orderId,
      type: type,
      content: '',
      createdById: state.order?.createdById ?? '',
      createdAt: DateTime.now(),
      localPath: (path ?? '').trim().isEmpty ? null : path,
      previewBytes: bytes == null ? null : Uint8List.fromList(bytes),
      fileName: fileName,
      isPendingUpload: true,
      hasUploadError: false,
    );
  }

  void _upsertOptimisticEvidence(ServiceOrderEvidenceModel item) {
    final order = state.order;
    if (order == null) return;
    final next = List<ServiceOrderEvidenceModel>.from(order.evidences)..add(item);
    state = state.copyWith(
      order: order.copyWith(evidences: next),
      clearActionError: true,
    );
  }

  void _replaceEvidence({
    required String temporaryId,
    required ServiceOrderEvidenceModel persisted,
  }) {
    final order = state.order;
    if (order == null) return;
    final next = order.evidences
        .map((evidence) => evidence.id == temporaryId ? persisted : evidence)
        .toList(growable: false);
    final updatedOrder = order.copyWith(evidences: next);
    state = state.copyWith(order: updatedOrder, clearActionError: true);
    ref.read(serviceOrdersListControllerProvider.notifier).upsertOrder(updatedOrder);
  }

  void _markEvidenceUploadFailed(String temporaryId, String message) {
    final order = state.order;
    if (order == null) return;
    final next = order.evidences
        .map(
          (evidence) => evidence.id == temporaryId
              ? evidence.copyWith(
                  isPendingUpload: false,
                  hasUploadError: true,
                )
              : evidence,
        )
        .toList(growable: false);
    state = state.copyWith(
      order: order.copyWith(evidences: next),
      actionError: message,
    );
  }
}