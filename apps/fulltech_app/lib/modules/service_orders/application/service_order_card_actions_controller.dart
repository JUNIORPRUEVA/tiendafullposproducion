import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../data/service_orders_api.dart';
import '../data/upload_repository.dart';
import '../service_order_models.dart';

/// State for a single card's quick actions.
class ServiceOrderCardActionState {
  final bool loading;
  final String? error;

  const ServiceOrderCardActionState({
    this.loading = false,
    this.error,
  });

  ServiceOrderCardActionState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return ServiceOrderCardActionState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Family provider for per-card actions (one controller per order ID).
final serviceOrderCardActionsProvider = StateNotifierProvider.autoDispose
    .family<
        ServiceOrderCardActionsController,
        ServiceOrderCardActionState,
        String>(
  (ref, orderId) {
    return ServiceOrderCardActionsController(
      orderId: orderId,
      ref: ref,
    );
  },
);

class ServiceOrderCardActionsController
    extends StateNotifier<ServiceOrderCardActionState> {
  final String orderId;
  final Ref ref;

  ServiceOrderCardActionsController({
    required this.orderId,
    required this.ref,
  }) : super(const ServiceOrderCardActionState());

  /// Change the order status and return the updated order.
  Future<ServiceOrderModel> changeStatus(ServiceOrderStatus newStatus) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(serviceOrdersApiProvider);
      final updated = await api.updateStatus(orderId, newStatus);
      state = state.copyWith(loading: false);
      return updated;
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo cambiar el estado';
      state = state.copyWith(loading: false, error: message);
      rethrow;
    }
  }

  /// Add text evidence to the order.
  Future<ServiceOrderEvidenceModel> addTextEvidence(String text) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(serviceOrdersApiProvider);
      final evidence = await api.addEvidence(
        orderId,
        CreateServiceOrderEvidenceRequest(
          type: ServiceEvidenceType.evidenciaTexto,
          content: text.trim(),
        ),
      );
      state = state.copyWith(loading: false);
      return evidence;
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo agregar la evidencia';
      state = state.copyWith(loading: false, error: message);
      rethrow;
    }
  }

  /// Upload image evidence to the order.
  Future<ServiceOrderEvidenceModel> addImageEvidence({
    required String fileName,
    List<int>? bytes,
    String? path,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(uploadRepositoryProvider);
      final uploaded = await repo.uploadImage(
        fileName: fileName,
        bytes: bytes,
        path: path,
      );
      final api = ref.read(serviceOrdersApiProvider);
      final evidence = await api.addEvidence(
        orderId,
        CreateServiceOrderEvidenceRequest(
          type: ServiceEvidenceType.evidenciaImagen,
          content: uploaded.url,
        ),
      );
      state = state.copyWith(loading: false);
      return evidence;
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo subir la imagen';
      state = state.copyWith(loading: false, error: message);
      rethrow;
    }
  }

  /// Upload video evidence to the order.
  Future<ServiceOrderEvidenceModel> addVideoEvidence({
    required String fileName,
    List<int>? bytes,
    String? path,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(uploadRepositoryProvider);
      final uploaded = await repo.uploadVideo(
        fileName: fileName,
        bytes: bytes,
        path: path,
      );
      final api = ref.read(serviceOrdersApiProvider);
      final evidence = await api.addEvidence(
        orderId,
        CreateServiceOrderEvidenceRequest(
          type: ServiceEvidenceType.evidenciaVideo,
          content: uploaded.url,
        ),
      );
      state = state.copyWith(loading: false);
      return evidence;
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo subir el video';
      state = state.copyWith(loading: false, error: message);
      rethrow;
    }
  }

  /// Add technical report to the order.
  Future<ServiceOrderReportModel> addTechnicalReport(String report) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final api = ref.read(serviceOrdersApiProvider);
      final result = await api.addReport(orderId, report.trim());
      state = state.copyWith(loading: false);
      return result;
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo guardar el reporte';
      state = state.copyWith(loading: false, error: message);
      rethrow;
    }
  }
}
