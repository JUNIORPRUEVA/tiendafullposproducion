import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

class TechnicalExecutionState {
  final bool loading;
  final bool saving;
  final String? error;
  final ServiceModel? service;
  final List<ServiceExecutionChangeModel> changes;
  final List<PendingEvidenceUpload> pendingEvidence;

  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String notes;
  final bool clientApproved;
  final Map<String, dynamic> phaseSpecificData;

  const TechnicalExecutionState({
    this.loading = false,
    this.saving = false,
    this.error,
    this.service,
    this.changes = const [],
    this.pendingEvidence = const [],
    this.arrivedAt,
    this.startedAt,
    this.finishedAt,
    this.notes = '',
    this.clientApproved = false,
    this.phaseSpecificData = const {},
  });

  bool get hasService => service != null && service!.id.trim().isNotEmpty;

  TechnicalExecutionState copyWith({
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
    ServiceModel? service,
    List<ServiceExecutionChangeModel>? changes,
    List<PendingEvidenceUpload>? pendingEvidence,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? notes,
    bool? clientApproved,
    Map<String, dynamic>? phaseSpecificData,
  }) {
    return TechnicalExecutionState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      service: service ?? this.service,
      changes: changes ?? this.changes,
      pendingEvidence: pendingEvidence ?? this.pendingEvidence,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      notes: notes ?? this.notes,
      clientApproved: clientApproved ?? this.clientApproved,
      phaseSpecificData: phaseSpecificData ?? this.phaseSpecificData,
    );
  }
}

final technicalExecutionControllerProvider =
    StateNotifierProvider.family<
      TechnicalExecutionController,
      TechnicalExecutionState,
      String
    >((ref, serviceId) {
      return TechnicalExecutionController(ref, serviceId);
    });

class TechnicalExecutionController
    extends StateNotifier<TechnicalExecutionState> {
  final Ref ref;
  final String serviceId;

  final LocalJsonCache _cache = LocalJsonCache();
  Timer? _saveDebounce;

  TechnicalExecutionController(this.ref, this.serviceId)
    : super(const TechnicalExecutionState()) {
    unawaited(load());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  String _cacheKey(String userId) => 'ops_exec|$userId|${serviceId.trim()}';

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);

    final auth = ref.read(authStateProvider);
    final user = auth.user;
    final userId = (user?.id ?? '').trim();

    try {
      final repo = ref.read(operationsRepositoryProvider);

      final service = await repo.getService(serviceId);

      ServiceExecutionBundleModel bundle = const ServiceExecutionBundleModel(
        report: null,
        changes: [],
      );
      String? reportError;
      try {
        bundle = await repo.getExecutionReport(serviceId: serviceId);
      } on ApiException catch (e) {
        reportError = e.message;
      } catch (e) {
        reportError = e.toString();
      }

      final draft = userId.isEmpty
          ? null
          : await _cache.readMap(_cacheKey(userId));

      DateTime? parseDate(dynamic raw) {
        if (raw == null) return null;
        return DateTime.tryParse(raw.toString());
      }

      Map<String, dynamic> parseMap(dynamic raw) {
        if (raw is Map) return raw.cast<String, dynamic>();
        return const <String, dynamic>{};
      }

      final arrivedAt = draft?['arrivedAt'] != null
          ? parseDate(draft!['arrivedAt'])
          : bundle.report?.arrivedAt;
      final startedAt = draft?['startedAt'] != null
          ? parseDate(draft!['startedAt'])
          : bundle.report?.startedAt;
      final finishedAt = draft?['finishedAt'] != null
          ? parseDate(draft!['finishedAt'])
          : bundle.report?.finishedAt;
      final notes = (draft?['notes'] ?? bundle.report?.notes ?? '').toString();
      final clientApproved =
          (draft?['clientApproved'] ??
              bundle.report?.clientApproved ??
              false) ==
          true;

      final phaseSpecificData = draft?['phaseSpecificData'] != null
          ? parseMap(draft!['phaseSpecificData'])
          : (bundle.report?.phaseSpecificData ?? const <String, dynamic>{});

      state = state.copyWith(
        loading: false,
        error: reportError,
        service: service,
        changes: bundle.changes,
        arrivedAt: arrivedAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
        notes: notes,
        clientApproved: clientApproved,
        phaseSpecificData: phaseSpecificData,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  String _guessMimeType(PlatformFile file) {
    final ext = (file.extension ?? '').trim().toLowerCase();
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'mp4') return 'video/mp4';
    return 'application/octet-stream';
  }

  String _guessMimeTypeFromName(String name) {
    final trimmed = name.trim();
    final idx = trimmed.lastIndexOf('.');
    final ext = idx >= 0 ? trimmed.substring(idx + 1).toLowerCase() : '';
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'mp4') return 'video/mp4';
    return 'application/octet-stream';
  }

  void _upsertPending(PendingEvidenceUpload next) {
    final list = state.pendingEvidence;
    final idx = list.indexWhere((e) => e.id == next.id);
    if (idx < 0) {
      state = state.copyWith(pendingEvidence: [next, ...list]);
      return;
    }

    final updated = [...list];
    updated[idx] = next;
    state = state.copyWith(pendingEvidence: updated);
  }

  void _removePending(String id) {
    final next = state.pendingEvidence.where((e) => e.id != id).toList();
    state = state.copyWith(pendingEvidence: next);
  }

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

  Future<void> _persistDraft() async {
    final userId = (ref.read(authStateProvider).user?.id ?? '').trim();
    if (userId.isEmpty) return;

    await _cache.writeMap(_cacheKey(userId), {
      'arrivedAt': state.arrivedAt?.toIso8601String(),
      'startedAt': state.startedAt?.toIso8601String(),
      'finishedAt': state.finishedAt?.toIso8601String(),
      'notes': state.notes,
      'clientApproved': state.clientApproved,
      'phaseSpecificData': state.phaseSpecificData,
      'at': DateTime.now().toIso8601String(),
    });
  }

  void updatePhaseSpecificField(String key, String value) {
    if (_readOnly) return;
    final k = key.trim();
    if (k.isEmpty) return;
    final v = value.trim();

    final next = <String, dynamic>{...state.phaseSpecificData};
    if (v.isEmpty) {
      next.remove(k);
    } else {
      next[k] = v;
    }

    state = state.copyWith(phaseSpecificData: next);
    unawaited(_persistDraft());
    _debouncedSave();
  }

  Future<void> _clearDraft() async {
    final userId = (ref.read(authStateProvider).user?.id ?? '').trim();
    if (userId.isEmpty) return;
    await _cache.remove(_cacheKey(userId));
  }

  void updateNotes(String value) {
    if (_readOnly) return;
    state = state.copyWith(notes: value);
    unawaited(_persistDraft());
    _debouncedSave();
  }

  void toggleClientApproved(bool value) {
    if (_readOnly) return;
    state = state.copyWith(clientApproved: value);
    unawaited(_persistDraft());
    _debouncedSave();
  }

  void markArrivedNow() {
    if (_readOnly) return;
    state = state.copyWith(arrivedAt: DateTime.now());
    unawaited(_persistDraft());
    unawaited(saveNow());
  }

  void markStartedNow() {
    if (_readOnly) return;
    state = state.copyWith(startedAt: DateTime.now());
    unawaited(_persistDraft());
    unawaited(saveNow());
  }

  void markFinishedNow() {
    if (_readOnly) return;
    state = state.copyWith(finishedAt: DateTime.now());
    unawaited(_persistDraft());
    unawaited(saveNow());
  }

  void _debouncedSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(saveNow());
    });
  }

  Future<void> saveNow() async {
    if (_readOnly) return;
    if (state.saving) return;

    final service = state.service;
    if (service == null) return;

    state = state.copyWith(saving: true, clearError: true);

    try {
      final repo = ref.read(operationsRepositoryProvider);
      final bundle = await repo.upsertExecutionReport(
        serviceId: serviceId,
        phase: service.currentPhase,
        arrivedAt: state.arrivedAt,
        startedAt: state.startedAt,
        finishedAt: state.finishedAt,
        notes: state.notes,
        phaseSpecificData: state.phaseSpecificData.isEmpty
            ? null
            : state.phaseSpecificData,
        clientApproved: state.clientApproved,
      );

      state = state.copyWith(saving: false, changes: bundle.changes);
      await _clearDraft();
    } on ApiException catch (e) {
      state = state.copyWith(saving: false, error: e.message);
    } catch (e) {
      state = state.copyWith(saving: false, error: e.toString());
    }
  }

  Future<void> toggleStep(ServiceStepModel step, bool next) async {
    if (_readOnly) return;
    final service = state.service;
    if (service == null) return;

    try {
      final repo = ref.read(operationsRepositoryProvider);
      await repo.addUpdate(
        serviceId: serviceId,
        type: 'step_update',
        stepId: step.id,
        stepDone: next,
      );

      final updatedSteps = service.steps
          .map(
            (s) => s.id == step.id
                ? ServiceStepModel(
                    id: s.id,
                    stepKey: s.stepKey,
                    stepLabel: s.stepLabel,
                    isDone: next,
                    doneAt: next ? DateTime.now() : null,
                  )
                : s,
          )
          .toList(growable: false);

      state = state.copyWith(service: service.copyWith(steps: updatedSteps));
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> uploadEvidence({
    required PlatformFile file,
    String? caption,
  }) async {
    if (_readOnly) return;
    final service = state.service;
    if (service == null) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final mimeType = _guessMimeType(file);
    final isVideo = mimeType.startsWith('video/');
    final trimmedCaption = (caption ?? '').trim();
    if (!isVideo && trimmedCaption.isEmpty) return;
    final kind = isVideo ? 'video_evidence' : 'evidence_final';

    _upsertPending(
      PendingEvidenceUpload(
        id: id,
        fileName: file.name,
        mimeType: mimeType,
        caption: trimmedCaption,
        fileSize: file.size,
        path: file.path,
        bytes: file.bytes,
      ),
    );

    try {
      final storage = ref.read(storageRepositoryProvider);

      final presign = await storage.presign(
        serviceId: serviceId,
        fileName: file.name,
        contentType: mimeType,
        fileSize: file.size,
        kind: kind,
      );

      if (!mounted) return;

      await storage.uploadToPresignedUrl(
        uploadUrl: presign.uploadUrl,
        bytes: file.bytes,
        stream: kIsWeb ? null : file.readStream,
        contentType: mimeType,
        contentLength: file.size,
        onProgress: (sent, total) {
          if (!mounted) return;
          if (total <= 0) return;
          final p = sent / total;
          final bounded = p < 0 ? 0.0 : (p > 1 ? 1.0 : p);
          final cur = state.pendingEvidence.firstWhere(
            (e) => e.id == id,
            orElse: () => PendingEvidenceUpload(
              id: id,
              fileName: file.name,
              mimeType: mimeType,
              caption: trimmedCaption,
              fileSize: file.size,
              path: file.path,
              bytes: file.bytes,
            ),
          );
          _upsertPending(cur.copyWith(progress: bounded));
        },
      );

      if (!mounted) return;

      await storage.confirm(
        serviceId: serviceId,
        objectKey: presign.objectKey,
        publicUrl: presign.publicUrl,
        fileName: file.name,
        mimeType: mimeType,
        fileSize: file.size,
        kind: kind,
        caption: trimmedCaption.isEmpty ? null : trimmedCaption,
      );

      if (!mounted) return;

      final repo = ref.read(operationsRepositoryProvider);
      final refreshed = await repo.getService(serviceId);

      if (!mounted) return;
      _removePending(id);
      state = state.copyWith(service: refreshed);
    } catch (e) {
      if (!mounted) return;
      _removePending(id);
      if (e is ApiException) {
        state = state.copyWith(error: e.message);
      } else {
        state = state.copyWith(error: e.toString());
      }
    }
  }

  Future<void> uploadEvidenceXFile({
    required XFile file,
    String? caption,
  }) async {
    if (_readOnly) return;
    final service = state.service;
    if (service == null) return;

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final mimeType = _guessMimeTypeFromName(file.name);
    final isVideo = mimeType.startsWith('video/');
    final trimmedCaption = (caption ?? '').trim();
    if (!isVideo && trimmedCaption.isEmpty) return;
    final kind = isVideo ? 'video_evidence' : 'evidence_final';

    int size;
    try {
      size = await file.length();
    } catch (_) {
      size = 0;
    }

    // For web uploads we must provide bytes. For mobile, only keep bytes for images
    // (to show a quick preview) and stream the upload when possible.
    List<int>? bytes;
    if (kIsWeb || (!isVideo)) {
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }

    _upsertPending(
      PendingEvidenceUpload(
        id: id,
        fileName: file.name,
        mimeType: mimeType,
        caption: trimmedCaption,
        fileSize: size,
        path: kIsWeb ? null : file.path,
        bytes: bytes,
      ),
    );

    try {
      final storage = ref.read(storageRepositoryProvider);

      final presign = await storage.presign(
        serviceId: serviceId,
        fileName: file.name,
        contentType: mimeType,
        fileSize: size,
        kind: kind,
      );

      if (!mounted) return;

      await storage.uploadToPresignedUrl(
        uploadUrl: presign.uploadUrl,
        bytes: bytes,
        stream: kIsWeb ? null : file.openRead(),
        contentType: mimeType,
        contentLength: size,
        onProgress: (sent, total) {
          if (!mounted) return;
          if (total <= 0) return;
          final p = sent / total;
          final bounded = p < 0 ? 0.0 : (p > 1 ? 1.0 : p);
          final cur = state.pendingEvidence.firstWhere(
            (e) => e.id == id,
            orElse: () => PendingEvidenceUpload(
              id: id,
              fileName: file.name,
              mimeType: mimeType,
              caption: trimmedCaption,
              fileSize: size,
              path: kIsWeb ? null : file.path,
              bytes: bytes,
            ),
          );
          _upsertPending(cur.copyWith(progress: bounded));
        },
      );

      if (!mounted) return;

      await storage.confirm(
        serviceId: serviceId,
        objectKey: presign.objectKey,
        publicUrl: presign.publicUrl,
        fileName: file.name,
        mimeType: mimeType,
        fileSize: size,
        kind: kind,
        caption: trimmedCaption.isEmpty ? null : trimmedCaption,
      );

      if (!mounted) return;

      final repo = ref.read(operationsRepositoryProvider);
      final refreshed = await repo.getService(serviceId);

      if (!mounted) return;
      _removePending(id);
      state = state.copyWith(service: refreshed);
    } catch (e) {
      if (!mounted) return;
      _removePending(id);
      if (e is ApiException) {
        state = state.copyWith(error: e.message);
      } else {
        state = state.copyWith(error: e.toString());
      }
    }
  }

  Future<void> addChange({
    required String type,
    required String description,
    double? quantity,
    double? extraCost,
    bool? clientApproved,
    String? note,
  }) async {
    if (_readOnly) return;
    if (type.trim().isEmpty || description.trim().isEmpty) return;

    try {
      final repo = ref.read(operationsRepositoryProvider);
      final created = await repo.addExecutionChange(
        serviceId: serviceId,
        type: type.trim(),
        description: description.trim(),
        quantity: quantity,
        extraCost: extraCost,
        clientApproved: clientApproved,
        note: note,
      );

      state = state.copyWith(changes: [...state.changes, created]);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> deleteChange(ServiceExecutionChangeModel change) async {
    if (_readOnly) return;

    final userId = (ref.read(authStateProvider).user?.id ?? '').trim();
    final canDeleteOwn = userId.isNotEmpty && change.createdByUserId == userId;
    final user = ref.read(authStateProvider).user;
    final perms = OperationsPermissions(user: user, service: state.service!);
    final canDelete = canDeleteOwn || perms.isAdminLike;
    if (!canDelete) return;

    try {
      final repo = ref.read(operationsRepositoryProvider);
      await repo.deleteExecutionChange(
        serviceId: serviceId,
        changeId: change.id,
      );

      state = state.copyWith(
        changes: state.changes.where((c) => c.id != change.id).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}
