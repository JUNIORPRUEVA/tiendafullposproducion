import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/user_model.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../../cotizaciones/cotizacion_models.dart';
import '../../cotizaciones/data/cotizaciones_repository.dart';
import '../data/service_orders_api.dart';
import '../data/upload_repository.dart';
import '../service_order_models.dart';
import '../../../features/user/data/users_repository.dart';

class CreateServiceOrderState {
  final bool loading;
  final bool submitting;
  final bool initialized;
  final String? error;
  final String? actionError;
  final List<ClienteModel> clients;
  final List<CotizacionModel> quotations;
  final List<UserModel> technicians;
  final List<ServiceOrderDraftEvidence> evidences;
  final ClienteModel? selectedClient;
  final CotizacionModel? selectedQuotation;
  final UserModel? selectedTechnician;
  final ServiceOrderCategory category;
  final ServiceOrderType? serviceType;
  final ServiceOrderModel? cloneSource;
  final String? quotationMessage;
  final bool uploadingEvidence;
  final double uploadProgress;
  final String? uploadLabel;

  const CreateServiceOrderState({
    this.loading = false,
    this.submitting = false,
    this.initialized = false,
    this.error,
    this.actionError,
    this.clients = const [],
    this.quotations = const [],
    this.technicians = const [],
    this.evidences = const [],
    this.selectedClient,
    this.selectedQuotation,
    this.selectedTechnician,
    this.category = ServiceOrderCategory.camara,
    this.serviceType,
    this.cloneSource,
    this.quotationMessage,
    this.uploadingEvidence = false,
    this.uploadProgress = 0,
    this.uploadLabel,
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
    List<ServiceOrderDraftEvidence>? evidences,
    ClienteModel? selectedClient,
    CotizacionModel? selectedQuotation,
    UserModel? selectedTechnician,
    ServiceOrderCategory? category,
    ServiceOrderType? serviceType,
    ServiceOrderModel? cloneSource,
    String? quotationMessage,
    bool? uploadingEvidence,
    double? uploadProgress,
    String? uploadLabel,
    bool clearError = false,
    bool clearActionError = false,
    bool clearSelectedQuotation = false,
    bool clearSelectedTechnician = false,
    bool clearQuotationMessage = false,
    bool clearUploadLabel = false,
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
        evidences: evidences ?? this.evidences,
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
      quotationMessage: clearQuotationMessage
          ? null
          : (quotationMessage ?? this.quotationMessage),
      uploadingEvidence: uploadingEvidence ?? this.uploadingEvidence,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadLabel: clearUploadLabel ? null : (uploadLabel ?? this.uploadLabel),
    );
  }
}

class CreateServiceOrderSubmissionResult {
  final ServiceOrderModel order;
  final String? warningMessage;

  const CreateServiceOrderSubmissionResult({
    required this.order,
    this.warningMessage,
  });
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
  AppRole get _currentRole =>
      ref.read(authStateProvider).user?.appRole ?? AppRole.unknown;
  bool get _isTechnician => _currentRole == AppRole.tecnico;

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
      clearQuotationMessage: true,
      loading: true,
    );
    if (client.telefono.trim().isEmpty) {
      state = state.copyWith(
        loading: false,
        quotations: const [],
        quotationMessage:
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
      } else if (quotations.length == 1) {
        selectedQuotation = quotations.first;
      }
      state = state.copyWith(
        loading: false,
        quotations: quotations,
        selectedQuotation: selectedQuotation,
        quotationMessage: quotations.isEmpty
            ? 'Este cliente no tiene cotizaciones'
            : quotations.length == 1
            ? 'Cotización seleccionada automáticamente'
            : 'Selecciona la cotización que deseas usar',
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
      quotationMessage: quotation == null
          ? state.quotationMessage
          : 'Cotización lista para crear la orden',
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

  void addTextEvidence(String content) {
    _ensureTechnicianEvidenceAccess();
    final normalized = content.trim();
    if (normalized.isEmpty) return;
    state = state.copyWith(
      evidences: [
        ...state.evidences,
        ServiceOrderDraftEvidence.text(
          id: _draftId(),
          content: normalized,
        ),
      ],
      clearActionError: true,
    );
  }

  Future<void> addVideoEvidence({
    required String fileName,
    List<int>? bytes,
    String? path,
    int? sizeBytes,
  }) async {
    _ensureTechnicianEvidenceAccess();
    await _withUploadState(
      label: 'Subiendo video',
      action: () async {
        final uploaded = await ref.read(uploadRepositoryProvider).uploadVideo(
              fileName: fileName,
              bytes: bytes,
              path: path,
              onProgress: _updateUploadProgress,
            );
        state = state.copyWith(
          evidences: [
            ...state.evidences,
            ServiceOrderDraftEvidence.video(
              id: _draftId(),
              uploadedUrl: uploaded.url,
              localPath: (path ?? '').trim().isEmpty ? null : path!.trim(),
              fileName: fileName,
              sizeBytes: sizeBytes ?? uploaded.size,
            ),
          ],
          clearActionError: true,
        );
      },
      fallbackMessage: 'No se pudo subir el video',
    );
  }

  Future<void> addImageEvidence({
    required String fileName,
    List<int>? bytes,
    String? path,
    int? sizeBytes,
  }) async {
    _ensureTechnicianEvidenceAccess();
    await _withUploadState(
      label: 'Subiendo imagen',
      action: () async {
        final uploaded = await ref.read(uploadRepositoryProvider).uploadImage(
              fileName: fileName,
              bytes: bytes,
              path: path,
              onProgress: _updateUploadProgress,
            );
        state = state.copyWith(
          evidences: [
            ...state.evidences,
            ServiceOrderDraftEvidence.image(
              id: _draftId(),
              uploadedUrl: uploaded.url,
              previewBytes: bytes == null ? null : Uint8List.fromList(bytes),
              localPath: (path ?? '').trim().isEmpty ? null : path!.trim(),
              fileName: fileName,
              sizeBytes: sizeBytes ?? uploaded.size,
            ),
          ],
          clearActionError: true,
        );
      },
      fallbackMessage: 'No se pudo subir la imagen',
    );
  }

  void removeEvidence(String id) {
    _ensureTechnicianEvidenceAccess();
    state = state.copyWith(
      evidences: state.evidences.where((item) => item.id != id).toList(),
      clearActionError: true,
    );
  }

  Future<CreateServiceOrderSubmissionResult> submit({
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

    final technicalNoteValue = _isTechnician ? technicalNote.trim() : '';
    final extraRequirementsValue = _isTechnician
        ? extraRequirements.trim()
        : '';
    final assignedToId = _isTechnician ? state.selectedTechnician?.id : null;

    state = state.copyWith(submitting: true, clearActionError: true);
    try {
      final result = state.isCloneMode
          ? await ref.read(serviceOrdersApiProvider).cloneOrder(
                state.cloneSource!.id,
                CloneServiceOrderRequest(
                  serviceType: serviceType,
                  technicalNote: technicalNoteValue,
                  extraRequirements: extraRequirementsValue,
                  assignedToId: assignedToId,
                ),
              )
          : await ref.read(serviceOrdersApiProvider).createOrder(
                CreateServiceOrderRequest(
                  clientId: client.id,
                  quotationId: quotation!.id,
                  category: state.category,
                  serviceType: serviceType,
                  technicalNote: technicalNoteValue,
                  extraRequirements: extraRequirementsValue,
                  assignedToId: assignedToId,
                ),
              );
      final warningMessage = await _sendDraftEvidences(result.id);
      state = state.copyWith(submitting: false);
      return CreateServiceOrderSubmissionResult(
        order: result,
        warningMessage: warningMessage,
      );
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo guardar la orden';
      state = state.copyWith(submitting: false, actionError: message);
      rethrow;
    }
  }

  Future<String?> _sendDraftEvidences(String orderId) async {
    if (state.evidences.isEmpty) return null;

    try {
      final api = ref.read(serviceOrdersApiProvider);

      for (final evidence in state.evidences) {
        await api.addEvidence(
          orderId,
          CreateServiceOrderEvidenceRequest(
            type: evidence.type,
            content: evidence.evidenceContent,
          ),
        );
      }

      return null;
    } catch (_) {
      return 'La orden fue creada, pero no se pudieron guardar todas las evidencias.';
    }
  }

  void _ensureTechnicianEvidenceAccess() {
    if (_isTechnician) return;
    throw ApiException('Solo el técnico puede gestionar evidencias desde esta pantalla');
  }

  void _updateUploadProgress(double progress) {
    state = state.copyWith(uploadProgress: progress.clamp(0, 1));
  }

  Future<void> _withUploadState({
    required String label,
    required Future<void> Function() action,
    required String fallbackMessage,
  }) async {
    state = state.copyWith(
      uploadingEvidence: true,
      uploadProgress: 0,
      uploadLabel: label,
      clearActionError: true,
    );
    try {
      await action();
      state = state.copyWith(
        uploadingEvidence: false,
        uploadProgress: 0,
        clearUploadLabel: true,
      );
    } catch (error) {
      final message = error is ApiException ? error.message : fallbackMessage;
      state = state.copyWith(
        uploadingEvidence: false,
        uploadProgress: 0,
        clearUploadLabel: true,
        actionError: message,
      );
      rethrow;
    }
  }

  String _draftId() => DateTime.now().microsecondsSinceEpoch.toString();
}