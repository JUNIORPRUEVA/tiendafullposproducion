import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/user_model.dart';
import '../../../core/realtime/operations_realtime_service.dart';
import '../../../core/utils/local_media_cache.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../../cotizaciones/cotizacion_models.dart';
import '../../cotizaciones/data/cotizaciones_repository.dart';
import '../data/service_orders_api.dart';
import '../data/service_orders_local_repository.dart';
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
  final CotizacionModel? quotation;
  final Map<String, UserModel> usersById;

  const ServiceOrderDetailState({
    this.loading = false,
    this.working = false,
    this.error,
    this.actionError,
    this.order,
    this.client,
    this.quotation,
    this.usersById = const {},
  });

  ServiceOrderDetailState copyWith({
    bool? loading,
    bool? working,
    String? error,
    String? actionError,
    ServiceOrderModel? order,
    ClienteModel? client,
    CotizacionModel? quotation,
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
      quotation: quotation ?? this.quotation,
      usersById: usersById ?? this.usersById,
    );
  }
}

final serviceOrderDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ServiceOrderDetailController, ServiceOrderDetailState, String>((
      ref,
      orderId,
    ) {
      final controller = ServiceOrderDetailController(ref, orderId)..load();
      final subscription = ref
          .read(operationsRealtimeServiceProvider)
          .stream
          .listen((message) {
            final directId = message.serviceId?.trim();
            final payloadId = message.service?['id']?.toString().trim();
            final targetId = directId != null && directId.isNotEmpty
                ? directId
                : payloadId;
            if (targetId != orderId) return;
            if (message.type == 'service.deleted') {
              controller.refresh();
              return;
            }
            controller.applyRealtimePayload(message.service);
          });
      ref.onDispose(subscription.cancel);
      return controller;
    });

class ServiceOrderDetailController
    extends StateNotifier<ServiceOrderDetailState> {
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
    if (state.order == null) {
      final listState = ref.read(serviceOrdersListControllerProvider);
      ServiceOrderModel? seededOrder;
      for (final item in listState.items) {
        if (item.id == orderId) {
          seededOrder = item;
          break;
        }
      }
      final seededClient =
          seededOrder?.client ??
          (seededOrder == null
              ? null
              : listState.clientsById[seededOrder.clientId]);
      if (seededOrder != null) {
        state = state.copyWith(
          loading: false,
          order: seededOrder,
          client: seededClient,
          usersById: listState.usersById,
          clearError: true,
          clearActionError: true,
        );
      }

      final cachedOrder = await ref
          .read(serviceOrdersLocalRepositoryProvider)
          .readOrder(orderId);
      final cachedClient =
          cachedOrder?.client ??
          await ref
              .read(serviceOrdersLocalRepositoryProvider)
              .readClientById(cachedOrder?.clientId ?? '');
      final cachedUsers = await ref
          .read(serviceOrdersLocalRepositoryProvider)
          .readUsersById();
        final cachedQuotation = (cachedOrder?.quotationId ?? '').trim().isEmpty
          ? null
          : await ref
            .read(cotizacionesRepositoryProvider)
            .getCachedById(cachedOrder!.quotationId!);

      if (cachedOrder != null) {
        state = state.copyWith(
          loading: false,
          order: cachedOrder,
          client: cachedClient,
          quotation: cachedQuotation,
          usersById: cachedUsers,
          clearError: true,
          clearActionError: true,
        );
      }
    }

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
          .getAllUsers(skipLoader: true)
          .catchError((_) => <UserModel>[]);
      final quotationFuture = (() async {
        final quotationId = (order.quotationId ?? '').trim();
        if (quotationId.isEmpty) return null;

        final repository = ref.read(cotizacionesRepositoryProvider);
        final cached = await repository.getCachedById(quotationId);
        try {
          return await repository.getByIdAndCache(quotationId);
        } catch (_) {
          return cached;
        }
      })();
      final fallbackClientFuture = order.client != null
          ? Future<ClienteModel?>.value(order.client)
          : ref
                .read(clientesRepositoryProvider)
                .getClientById(
                  ownerId: '',
                  id: order.clientId,
                  skipLoader: true,
                )
                .then<ClienteModel?>((value) => value)
                .catchError((_) => null);
      final results = await Future.wait<dynamic>([
        fallbackClientFuture,
        usersFuture,
        quotationFuture,
      ]);
      final client = results[0] as ClienteModel?;
      final users = results[1] as List<UserModel>;
      final quotation = results[2] as CotizacionModel?;
      final usersById = {for (final user in users) user.id: user};
      final mergedOrder = _mergeRemoteOrderWithLocalState(order);
      state = state.copyWith(
        loading: false,
        order: mergedOrder,
        client: client,
        quotation: quotation,
        usersById: usersById,
      );
      await ref
          .read(serviceOrdersLocalRepositoryProvider)
          .saveOrder(order: mergedOrder, client: client, usersById: usersById);
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

  void applyRealtimePayload(Map<String, dynamic>? payload) {
    if (payload == null) {
      unawaited(refresh());
      return;
    }

    try {
      final updated = _mergeRemoteOrderWithLocalState(
        ServiceOrderModel.fromJson(payload),
      );
      state = state.copyWith(
        order: updated,
        client: updated.client ?? state.client,
      );
      ref
          .read(serviceOrdersListControllerProvider.notifier)
          .upsertOrder(updated);
      unawaited(
        ref
            .read(serviceOrdersLocalRepositoryProvider)
            .saveOrder(
              order: updated,
              client: updated.client ?? state.client,
              usersById: state.usersById,
            ),
      );
    } catch (_) {
      unawaited(refresh());
    }
  }

  Future<void> updateOperationalDetails({
    required String? technicalNote,
    required String? extraRequirements,
  }) async {
    final currentOrder = state.order;
    if (currentOrder == null) return;

    state = state.copyWith(working: true, clearActionError: true);
    try {
      final updated = await ref
          .read(serviceOrdersApiProvider)
          .updateOrder(
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
      ref
          .read(serviceOrdersListControllerProvider.notifier)
          .upsertOrder(updated);
      await ref
          .read(serviceOrdersLocalRepositoryProvider)
          .saveOrder(
            order: updated,
            client: updated.client ?? state.client,
            usersById: state.usersById,
          );
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
      final updated = await ref
          .read(serviceOrdersApiProvider)
          .updateStatus(orderId, status);
      state = state.copyWith(working: false, order: updated);
      ref
          .read(serviceOrdersListControllerProvider.notifier)
          .upsertOrder(updated);
      await ref
          .read(serviceOrdersLocalRepositoryProvider)
          .saveOrder(
            order: updated,
            client: updated.client ?? state.client,
            usersById: state.usersById,
          );
    } catch (error) {
      final message = _friendlyOrderMessage(
        error,
        fallback: 'No se pudo actualizar el estado',
        forbiddenMessage:
            'No tienes permiso para cambiar el estado de esta orden',
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

  Future<void> deleteOrder() async {
    final currentOrder = state.order;
    if (currentOrder == null) return;

    state = state.copyWith(working: true, clearActionError: true);
    try {
      await ref.read(serviceOrdersApiProvider).deleteOrder(orderId);
      await ref.read(serviceOrdersLocalRepositoryProvider).deleteOrder(orderId);
      await ref.read(serviceOrdersListControllerProvider.notifier).refresh();
      state = state.copyWith(working: false);
    } catch (error) {
      final message = _friendlyOrderMessage(
        error,
        fallback: 'No se pudo eliminar la orden',
        forbiddenMessage: 'No tienes permiso para eliminar esta orden',
      );
      state = state.copyWith(working: false, actionError: message);
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
    final cachedPath = await saveLocalMediaCopy(
      module: 'service_orders',
      scopeId: orderId,
      fileName: fileName,
      bytes: bytes,
      sourcePath: path,
    );
    final optimistic = _buildOptimisticEvidence(
      type: ServiceEvidenceType.evidenciaImagen,
      fileName: fileName,
      path: cachedPath ?? path,
      bytes: bytes,
    );
    _upsertOptimisticEvidence(optimistic);

    unawaited(
      _enqueueUpload(() async {
        try {
          final uploaded = await ref
              .read(uploadRepositoryProvider)
              .uploadImage(bytes: bytes, path: path, fileName: fileName);
          final saved = await ref
              .read(serviceOrdersApiProvider)
              .addEvidence(
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
    final cachedPath = await saveLocalMediaCopy(
      module: 'service_orders',
      scopeId: orderId,
      fileName: fileName,
      bytes: bytes,
      sourcePath: path,
    );
    final optimistic = _buildOptimisticEvidence(
      type: ServiceEvidenceType.evidenciaVideo,
      fileName: fileName,
      path: cachedPath ?? path,
      bytes: bytes,
    );
    _upsertOptimisticEvidence(optimistic);

    unawaited(
      _enqueueUpload(() async {
        try {
          final uploaded = await ref
              .read(uploadRepositoryProvider)
              .uploadVideo(fileName: fileName, bytes: bytes, path: path);
          final saved = await ref
              .read(serviceOrdersApiProvider)
              .addEvidence(
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
        forbiddenMessage:
            'No tienes permiso para agregar reportes en esta orden',
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
        forbiddenMessage:
            'No tienes permiso para agregar evidencias en esta orden',
      );
      state = state.copyWith(working: false, actionError: message);
      rethrow;
    }
  }

  Future<void> _enqueueUpload(Future<void> Function() task) {
    _uploadQueue = _uploadQueue.then((_) => task()).catchError((_) {});
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
    final next = List<ServiceOrderEvidenceModel>.from(order.evidences)
      ..add(item);
    final updatedOrder = order.copyWith(evidences: next);
    state = state.copyWith(order: updatedOrder, clearActionError: true);
    ref
        .read(serviceOrdersListControllerProvider.notifier)
        .upsertOrder(updatedOrder);
    unawaited(
      ref
          .read(serviceOrdersLocalRepositoryProvider)
          .saveOrder(
            order: updatedOrder,
            client: updatedOrder.client ?? state.client,
            usersById: state.usersById,
          ),
    );
  }

  void _replaceEvidence({
    required String temporaryId,
    required ServiceOrderEvidenceModel persisted,
  }) {
    final order = state.order;
    if (order == null) return;
    final next = <ServiceOrderEvidenceModel>[];
    final seenIds = <String>{};
    for (final evidence in order.evidences) {
      final resolved = evidence.id == temporaryId
          ? persisted.copyWith(
              localPath: evidence.localPath,
              previewBytes: evidence.previewBytes,
              fileName: evidence.fileName,
              isPendingUpload: false,
              hasUploadError: false,
            )
          : evidence;
      if (seenIds.add(resolved.id)) {
        next.add(resolved);
      }
    }
    final updatedOrder = order.copyWith(evidences: next);
    state = state.copyWith(order: updatedOrder, clearActionError: true);
    ref
        .read(serviceOrdersListControllerProvider.notifier)
        .upsertOrder(updatedOrder);
    unawaited(
      ref
          .read(serviceOrdersLocalRepositoryProvider)
          .saveOrder(
            order: updatedOrder,
            client: updatedOrder.client ?? state.client,
            usersById: state.usersById,
          ),
    );
  }

  void _markEvidenceUploadFailed(String temporaryId, String message) {
    final order = state.order;
    if (order == null) return;
    final next = order.evidences
        .map(
          (evidence) => evidence.id == temporaryId
              ? evidence.copyWith(isPendingUpload: false, hasUploadError: true)
              : evidence,
        )
        .toList(growable: false);
    final updatedOrder = order.copyWith(evidences: next);
    state = state.copyWith(order: updatedOrder, actionError: message);
    ref
        .read(serviceOrdersListControllerProvider.notifier)
        .upsertOrder(updatedOrder);
    unawaited(
      ref
          .read(serviceOrdersLocalRepositoryProvider)
          .saveOrder(
            order: updatedOrder,
            client: updatedOrder.client ?? state.client,
            usersById: state.usersById,
          ),
    );
  }

  ServiceOrderModel _mergeRemoteOrderWithLocalState(ServiceOrderModel remote) {
    final localOrder = state.order;
    if (localOrder == null) return remote;

    final localOnlyEvidence = localOrder.evidences
        .where((evidence) {
          return evidence.isPendingUpload || evidence.hasUploadError;
        })
        .toList(growable: false);

    if (localOnlyEvidence.isEmpty) {
      return remote;
    }

    final next = List<ServiceOrderEvidenceModel>.from(remote.evidences);
    final seenIds = {for (final evidence in next) evidence.id};
    for (final evidence in localOnlyEvidence) {
      if (seenIds.add(evidence.id)) {
        next.add(evidence);
      }
    }
    next.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return remote.copyWith(evidences: next);
  }
}
