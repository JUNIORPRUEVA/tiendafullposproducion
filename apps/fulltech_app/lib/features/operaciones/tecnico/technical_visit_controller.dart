import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/storage/storage_repository.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import 'technical_evidence_upload.dart';
import 'technical_visit_models.dart';

class TechnicalVisitState {
  final bool loading;
  final bool refreshing;
  final bool saving;
  final String? error;

  final ServiceModel? service;
  final TechnicalVisitModel? visit;

  final String reportDescription;
  final String installationNotes;
  final List<EstimatedProductItemModel> estimatedProducts;
  final List<String> photos;
  final List<String> videos;
  final List<PendingEvidenceUpload> pendingUploads;

  const TechnicalVisitState({
    this.loading = false,
    this.refreshing = false,
    this.saving = false,
    this.error,
    this.service,
    this.visit,
    this.reportDescription = '',
    this.installationNotes = '',
    this.estimatedProducts = const [],
    this.photos = const [],
    this.videos = const [],
    this.pendingUploads = const [],
  });

  TechnicalVisitState copyWith({
    bool? loading,
    bool? refreshing,
    bool? saving,
    String? error,
    bool clearError = false,
    ServiceModel? service,
    TechnicalVisitModel? visit,
    String? reportDescription,
    String? installationNotes,
    List<EstimatedProductItemModel>? estimatedProducts,
    List<String>? photos,
    List<String>? videos,
    List<PendingEvidenceUpload>? pendingUploads,
  }) {
    return TechnicalVisitState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      service: service ?? this.service,
      visit: visit ?? this.visit,
      reportDescription: reportDescription ?? this.reportDescription,
      installationNotes: installationNotes ?? this.installationNotes,
      estimatedProducts: estimatedProducts ?? this.estimatedProducts,
      photos: photos ?? this.photos,
      videos: videos ?? this.videos,
      pendingUploads: pendingUploads ?? this.pendingUploads,
    );
  }
}

final technicalVisitControllerProvider =
    StateNotifierProvider.family<
      TechnicalVisitController,
      TechnicalVisitState,
      String
    >((ref, serviceId) {
      return TechnicalVisitController(ref, serviceId);
    });

class TechnicalVisitController extends StateNotifier<TechnicalVisitState> {
  final Ref ref;
  final String serviceId;

  final LocalJsonCache _cache = LocalJsonCache();
  Timer? _saveDebounce;

  TechnicalVisitController(this.ref, this.serviceId)
    : super(const TechnicalVisitState()) {
    unawaited(load());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  String _cacheKey(String userId) => 'ops_visit|$userId|${serviceId.trim()}';

  bool get _readOnly {
    final user = ref.read(authStateProvider).user;
    final service = state.service;
    if (service == null) return true;

    final perms = OperationsPermissions(user: user, service: service);
    if (!perms.canOperate) return true;
    if (perms.isAdminLike) return false;

    final status = parseStatus(service.status);
    return status == ServiceStatus.closed ||
        status == ServiceStatus.cancelled ||
        status == ServiceStatus.completed;
  }

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, refreshing: false, clearError: true);

    final auth = ref.read(authStateProvider);
    final userId = (auth.user?.id ?? '').trim();
    final cacheScope = userId;

    try {
      final repo = ref.read(operationsRepositoryProvider);
      final cachedService = cacheScope.isEmpty
          ? null
          : await repo.getCachedService(cacheScope: cacheScope, id: serviceId);
      final cachedVisit = cacheScope.isEmpty
          ? null
          : await repo.getCachedTechnicalVisitByOrder(
              cacheScope: cacheScope,
              orderId: serviceId,
            );

      Map<String, dynamic>? draft;
      if (userId.isNotEmpty) {
        draft = await _cache.readMap(_cacheKey(userId));
      }

      List<String> readUrls(dynamic raw) {
        if (raw is! List) return const [];
        return raw
            .map((e) => (e ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .toList(growable: false);
      }

      List<EstimatedProductItemModel> readProducts(dynamic raw) {
        if (raw is! List) return const [];
        return raw
            .whereType<Map>()
            .map(
              (m) =>
                  EstimatedProductItemModel.fromJson(m.cast<String, dynamic>()),
            )
            .where((p) => p.name.trim().isNotEmpty)
            .toList(growable: false);
      }

      final report =
          (draft?['report_description'] ??
                  draft?['reportDescription'] ??
                  cachedVisit?.reportDescription ??
                  '')
              .toString();
      final notes =
          (draft?['installation_notes'] ??
                  draft?['installationNotes'] ??
                  cachedVisit?.installationNotes ??
                  '')
              .toString();

      final products = draft != null && draft.containsKey('estimated_products')
          ? readProducts(draft['estimated_products'])
          : (cachedVisit?.estimatedProducts ?? const <EstimatedProductItemModel>[]);

      final photos = draft != null && draft.containsKey('photos')
          ? readUrls(draft['photos'])
          : (cachedVisit?.photos ?? const <String>[]);

      final videos = draft != null && draft.containsKey('videos')
          ? readUrls(draft['videos'])
          : (cachedVisit?.videos ?? const <String>[]);

      final hasCached = cachedService != null || cachedVisit != null;

      if (hasCached) {
        state = state.copyWith(
          loading: false,
          refreshing: true,
          service: cachedService,
          visit: cachedVisit,
          reportDescription: report,
          installationNotes: notes,
          estimatedProducts: products,
          photos: photos,
          videos: videos,
        );
      }

      final service = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: hasCached,
            );
      final visit = cacheScope.isEmpty
          ? await repo.getTechnicalVisitByOrder(serviceId)
          : await repo.getTechnicalVisitByOrderAndCache(
              cacheScope: cacheScope,
              orderId: serviceId,
            );

      state = state.copyWith(
        loading: false,
        refreshing: false,
        service: service,
        visit: visit,
        reportDescription: report,
        installationNotes: notes,
        estimatedProducts: products,
        photos: photos,
        videos: videos,
      );
    } on ApiException catch (e) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _persistDraft() async {
    final userId = (ref.read(authStateProvider).user?.id ?? '').trim();
    if (userId.isEmpty) return;

    await _cache.writeMap(_cacheKey(userId), {
      'report_description': state.reportDescription,
      'installation_notes': state.installationNotes,
      'estimated_products': state.estimatedProducts
          .map((e) => e.toJson())
          .toList(),
      'photos': state.photos,
      'videos': state.videos,
    });
  }

  void _scheduleDraftPersist() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persistDraft());
    });
  }

  void setReportDescription(String v) {
    state = state.copyWith(reportDescription: v, clearError: true);
    _scheduleDraftPersist();
  }

  void setInstallationNotes(String v) {
    state = state.copyWith(installationNotes: v, clearError: true);
    _scheduleDraftPersist();
  }

  void addEstimatedProduct(EstimatedProductItemModel item) {
    final name = item.name.trim();
    if (name.isEmpty) return;
    final qty = item.quantity <= 0 ? 1 : item.quantity;

    final list = [...state.estimatedProducts];
    list.add(EstimatedProductItemModel(name: name, quantity: qty));
    state = state.copyWith(estimatedProducts: list, clearError: true);
    _scheduleDraftPersist();
  }

  void removeEstimatedProductAt(int idx) {
    final list = [...state.estimatedProducts];
    if (idx < 0 || idx >= list.length) return;
    list.removeAt(idx);
    state = state.copyWith(estimatedProducts: list, clearError: true);
    _scheduleDraftPersist();
  }

  void removePhotoAt(int idx) {
    final list = [...state.photos];
    if (idx < 0 || idx >= list.length) return;
    list.removeAt(idx);
    state = state.copyWith(photos: list, clearError: true);
    _scheduleDraftPersist();
  }

  void removeVideoAt(int idx) {
    final list = [...state.videos];
    if (idx < 0 || idx >= list.length) return;
    list.removeAt(idx);
    state = state.copyWith(videos: list, clearError: true);
    _scheduleDraftPersist();
  }

  void _upsertPending(PendingEvidenceUpload next) {
    final list = state.pendingUploads;
    final idx = list.indexWhere((e) => e.id == next.id);
    if (idx < 0) {
      state = state.copyWith(pendingUploads: [next, ...list]);
      return;
    }

    final updated = [...list];
    updated[idx] = next;
    state = state.copyWith(pendingUploads: updated);
  }

  void _removePending(String id) {
    final next = state.pendingUploads.where((e) => e.id != id).toList();
    state = state.copyWith(pendingUploads: next);
  }

  String _guessMimeTypeFromName(String name, {required bool isVideo}) {
    final trimmed = name.trim();
    final idx = trimmed.lastIndexOf('.');
    final ext = idx >= 0 ? trimmed.substring(idx + 1).toLowerCase() : '';

    if (!isVideo) {
      if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
      if (ext == 'png') return 'image/png';
      if (ext == 'webp') return 'image/webp';
      return 'image/jpeg';
    }

    if (ext == 'mp4') return 'video/mp4';
    return 'video/mp4';
  }

  Future<void> uploadPhoto(XFile file) async {
    if (_readOnly) return;

    final fileName = file.name.trim().isEmpty ? 'photo.jpg' : file.name.trim();
    final mimeType = _guessMimeTypeFromName(fileName, isVideo: false);
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      final bytes = await file.readAsBytes();
      final pending = PendingEvidenceUpload(
        id: id,
        fileName: fileName,
        mimeType: mimeType,
        caption: 'Levantamiento',
        fileSize: bytes.length,
        bytes: bytes,
      );
      _upsertPending(pending);

      final storage = ref.read(storageRepositoryProvider);
      final presign = await storage.presign(
        serviceId: serviceId,
        fileName: fileName,
        contentType: mimeType,
        fileSize: bytes.length,
        kind: 'reference_photo',
      );

      await storage.uploadToPresignedUrl(
        uploadUrl: presign.uploadUrl,
        bytes: bytes,
        contentType: mimeType,
        contentLength: bytes.length,
        onProgress: (sent, total) {
          final progress = total <= 0 ? 0.0 : sent / total;
          _upsertPending(pending.copyWith(progress: progress));
        },
      );

      final confirmed = await storage.confirm(
        serviceId: serviceId,
        objectKey: presign.objectKey,
        publicUrl: presign.publicUrl,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: bytes.length,
        kind: 'reference_photo',
        caption: 'Levantamiento',
      );

      final nextPhotos = [...state.photos, confirmed.fileUrl];
      state = state.copyWith(photos: nextPhotos, clearError: true);
      _removePending(id);
      await _persistDraft();
      await save();
    } catch (e) {
      _upsertPending(
        PendingEvidenceUpload(
          id: id,
          fileName: fileName,
          mimeType: mimeType,
          caption: 'Levantamiento',
          fileSize: 0,
          progress: 1,
          status: PendingEvidenceStatus.failed,
        ),
      );
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> uploadVideo(XFile file) async {
    if (_readOnly) return;

    final fileName = file.name.trim().isEmpty ? 'video.mp4' : file.name.trim();
    final mimeType = _guessMimeTypeFromName(fileName, isVideo: true);
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      final bytes = await file.readAsBytes();
      final pending = PendingEvidenceUpload(
        id: id,
        fileName: fileName,
        mimeType: mimeType,
        caption: 'Levantamiento',
        fileSize: bytes.length,
        bytes: bytes,
      );
      _upsertPending(pending);

      final storage = ref.read(storageRepositoryProvider);
      final presign = await storage.presign(
        serviceId: serviceId,
        fileName: fileName,
        contentType: mimeType,
        fileSize: bytes.length,
        kind: 'video_evidence',
      );

      await storage.uploadToPresignedUrl(
        uploadUrl: presign.uploadUrl,
        bytes: bytes,
        contentType: mimeType,
        contentLength: bytes.length,
        onProgress: (sent, total) {
          final progress = total <= 0 ? 0.0 : sent / total;
          _upsertPending(pending.copyWith(progress: progress));
        },
      );

      final confirmed = await storage.confirm(
        serviceId: serviceId,
        objectKey: presign.objectKey,
        publicUrl: presign.publicUrl,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: bytes.length,
        kind: 'video_evidence',
        caption: 'Levantamiento',
      );

      final nextVideos = [...state.videos, confirmed.fileUrl];
      state = state.copyWith(videos: nextVideos, clearError: true);
      _removePending(id);
      await _persistDraft();
      await save();
    } catch (e) {
      _upsertPending(
        PendingEvidenceUpload(
          id: id,
          fileName: fileName,
          mimeType: mimeType,
          caption: 'Levantamiento',
          fileSize: 0,
          progress: 1,
          status: PendingEvidenceStatus.failed,
        ),
      );
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> save() async {
    if (_readOnly) return;
    if (state.saving) return;

    final auth = ref.read(authStateProvider);
    final userId = (auth.user?.id ?? '').trim();
    if (userId.isEmpty) {
      state = state.copyWith(error: 'Usuario no autenticado');
      return;
    }

    state = state.copyWith(saving: true, clearError: true);

    try {
      final repo = ref.read(operationsRepositoryProvider);
      final visit = state.visit;

      final basePayload = <String, dynamic>{
        'report_description': state.reportDescription,
        'installation_notes': state.installationNotes,
        'estimated_products': state.estimatedProducts
            .map((e) => e.toJson())
            .toList(),
        'photos': state.photos,
        'videos': state.videos,
        'visit_date': DateTime.now().toUtc().toIso8601String(),
      };

      final queued = await repo.saveTechnicalVisitOrQueue(
        scope: userId,
        serviceId: serviceId,
        technicianId: userId,
        visitId: visit?.id,
        payload: basePayload,
      );

      state = state.copyWith(
        saving: false,
        error: queued
            ? 'Levantamiento guardado localmente. Se sincronizará en segundo plano.'
            : null,
      );
      await _persistDraft();
    } on ApiException catch (e) {
      state = state.copyWith(saving: false, error: e.message);
    } catch (e) {
      state = state.copyWith(saving: false, error: e.toString());
    }
  }
}
