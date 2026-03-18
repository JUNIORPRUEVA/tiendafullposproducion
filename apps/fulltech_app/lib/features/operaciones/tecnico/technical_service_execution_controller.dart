import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/debug/trace_log.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/storage/storage_repository.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';
import 'technical_evidence_upload.dart';
import 'application/tech_operations_controller.dart';
import '../application/operations_controller.dart';

class TechnicalExecutionState {
  final bool loading;
  final bool refreshing;
  final bool savingReport;
  final bool savingUpdate;
  final String? error;
  final ServiceModel? service;
  final List<ServiceExecutionChangeModel> changes;
  final List<PendingEvidenceUpload> pendingEvidence;

  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String notes;
  final bool clientApproved;
  final Map<String, dynamic> checklistData;
  final Map<String, dynamic> phaseSpecificData;
  final List<ServiceChecklistTemplateModel> dynamicChecklists;

  const TechnicalExecutionState({
    this.loading = false,
    this.refreshing = false,
    this.savingReport = false,
    this.savingUpdate = false,
    this.error,
    this.service,
    this.changes = const [],
    this.pendingEvidence = const [],
    this.arrivedAt,
    this.startedAt,
    this.finishedAt,
    this.notes = '',
    this.clientApproved = false,
    this.checklistData = const {},
    this.phaseSpecificData = const {},
    this.dynamicChecklists = const [],
  });

  bool get hasService => service != null && service!.id.trim().isNotEmpty;

  bool get busy {
    if (loading) return true;
    if (savingReport || savingUpdate) return true;
    return pendingEvidence.any(
      (e) => e.status == PendingEvidenceStatus.uploading,
    );
  }

  TechnicalExecutionState copyWith({
    bool? loading,
    bool? refreshing,
    bool? savingReport,
    bool? savingUpdate,
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
    Map<String, dynamic>? checklistData,
    Map<String, dynamic>? phaseSpecificData,
    List<ServiceChecklistTemplateModel>? dynamicChecklists,
  }) {
    return TechnicalExecutionState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      savingReport: savingReport ?? this.savingReport,
      savingUpdate: savingUpdate ?? this.savingUpdate,
      error: clearError ? null : (error ?? this.error),
      service: service ?? this.service,
      changes: changes ?? this.changes,
      pendingEvidence: pendingEvidence ?? this.pendingEvidence,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      notes: notes ?? this.notes,
      clientApproved: clientApproved ?? this.clientApproved,
      checklistData: checklistData ?? this.checklistData,
      phaseSpecificData: phaseSpecificData ?? this.phaseSpecificData,
      dynamicChecklists: dynamicChecklists ?? this.dynamicChecklists,
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
  static const String _signatureSyncLocalSaved = 'local_saved';
  static const String _signatureSyncUploading = 'uploading';
  static const String _signatureSyncPendingUpload = 'pending_upload';
  static const String _signatureSyncCompleted = 'completed';

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

  Map<String, dynamic>? _clientSignatureMap([Map<String, dynamic>? source]) {
    final raw = (source ?? state.phaseSpecificData)['clientSignature'];
    if (raw is Map) return raw.cast<String, dynamic>();
    return null;
  }

  void _setClientSignatureMeta(Map<String, dynamic> meta) {
    final next = <String, dynamic>{...state.phaseSpecificData};
    next['clientSignature'] = meta;
    state = state.copyWith(phaseSpecificData: next, clearError: true);
  }

  Map<String, dynamic>? _phaseSpecificDataForRemote() {
    if (state.phaseSpecificData.isEmpty) return null;

    final next = <String, dynamic>{...state.phaseSpecificData};
    final signature = _clientSignatureMap(next);
    if (signature != null) {
      final cleaned = <String, dynamic>{
        if ((signature['fileId'] ?? '').toString().trim().isNotEmpty)
          'fileId': (signature['fileId'] ?? '').toString().trim(),
        if ((signature['fileUrl'] ?? '').toString().trim().isNotEmpty)
          'fileUrl': (signature['fileUrl'] ?? '').toString().trim(),
        if ((signature['signedAt'] ?? '').toString().trim().isNotEmpty)
          'signedAt': (signature['signedAt'] ?? '').toString().trim(),
      };
      if (cleaned.isEmpty) {
        next.remove('clientSignature');
      } else {
        next['clientSignature'] = cleaned;
      }
    }

    return next.isEmpty ? null : next;
  }

  bool _shouldKeepDraftAfterSave() {
    final signature = _clientSignatureMap();
    if (signature == null) return false;
    final localPreview = (signature['localPreviewBase64'] ?? '')
        .toString()
        .trim();
    final syncStatus = (signature['syncStatus'] ?? '').toString().trim();
    if (localPreview.isEmpty) return false;
    return syncStatus == _signatureSyncLocalSaved ||
        syncStatus == _signatureSyncUploading ||
        syncStatus == _signatureSyncPendingUpload;
  }

  void _syncServiceLists(ServiceModel service) {
    // Immediate in-memory updates (no network) for current device.
    ref
        .read(operationsControllerProvider.notifier)
        .applyRealtimeService(service);
    ref
        .read(techOperationsControllerProvider.notifier)
        .applyRealtimeService(service);
  }

  String _resolveTechnicianId(ServiceModel service) {
    final user = ref.read(authStateProvider).user;
    final currentUserId = (user?.id ?? '').trim();
    final currentUserRole = (user?.role ?? '').trim().toLowerCase();
    if (currentUserRole == 'tecnico' && currentUserId.isNotEmpty) {
      return currentUserId;
    }

    final directTechnicianId = (service.technicianId ?? '').trim();
    if (directTechnicianId.isNotEmpty) {
      return directTechnicianId;
    }

    for (final assignment in service.assignments) {
      final assignedUserId = assignment.userId.trim();
      if (assignedUserId.isNotEmpty) {
        return assignedUserId;
      }
    }

    return '';
  }

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, refreshing: false, clearError: true);

    final auth = ref.read(authStateProvider);
    final user = auth.user;
    final userId = (user?.id ?? '').trim();
    final cacheScope = userId;

    try {
      final repo = ref.read(operationsRepositoryProvider);

      final cachedService = cacheScope.isEmpty
          ? null
          : await repo.getCachedService(cacheScope: cacheScope, id: serviceId);
      final cachedBundle = cacheScope.isEmpty
          ? null
          : await repo.getCachedExecutionReport(
              cacheScope: cacheScope,
              serviceId: serviceId,
              technicianId: userId,
            );
      final cachedChecklist = cacheScope.isEmpty
          ? null
          : await repo.getCachedServiceChecklists(
              cacheScope: cacheScope,
              serviceId: serviceId,
            );

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

      final cachedReport = cachedBundle?.report;
      final arrivedAt = draft?['arrivedAt'] != null
          ? parseDate(draft!['arrivedAt'])
          : cachedReport?.arrivedAt;
      final startedAt = draft?['startedAt'] != null
          ? parseDate(draft!['startedAt'])
          : cachedReport?.startedAt;
      final finishedAt = draft?['finishedAt'] != null
          ? parseDate(draft!['finishedAt'])
          : cachedReport?.finishedAt;
      final notes = (draft?['notes'] ?? cachedReport?.notes ?? '').toString();
      final clientApproved =
          (draft?['clientApproved'] ?? cachedReport?.clientApproved ?? false) ==
          true;

      final phaseSpecificData = draft?['phaseSpecificData'] != null
          ? parseMap(draft!['phaseSpecificData'])
          : (cachedReport?.phaseSpecificData ?? const <String, dynamic>{});

      final checklistData = draft?['checklistData'] != null
          ? parseMap(draft!['checklistData'])
          : (cachedReport?.checklistData ?? const <String, dynamic>{});

      final hasCached =
          cachedService != null ||
          cachedBundle != null ||
          cachedChecklist != null;

      if (hasCached) {
        state = state.copyWith(
          loading: false,
          refreshing: true,
          service: cachedService,
          changes: cachedBundle?.changes ?? state.changes,
          arrivedAt: arrivedAt,
          startedAt: startedAt,
          finishedAt: finishedAt,
          notes: notes,
          clientApproved: clientApproved,
          checklistData: checklistData,
          phaseSpecificData: phaseSpecificData,
          dynamicChecklists:
              cachedChecklist?.templates ?? state.dynamicChecklists,
        );
      }

      final service = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: hasCached,
            );

      ServiceExecutionBundleModel bundle =
          cachedBundle ??
          const ServiceExecutionBundleModel(report: null, changes: []);
      ServiceChecklistBundleModel checklistBundle =
          cachedChecklist ??
          const ServiceChecklistBundleModel(
            serviceId: '',
            currentPhase: '',
            orderState: '',
            categoryCode: '',
            categoryLabel: '',
            templates: [],
          );
        String? reportError;
        String? checklistError;
        try {
        bundle = cacheScope.isEmpty
            ? await repo.getExecutionReport(
                serviceId: serviceId,
                technicianId: userId,
              )
            : await repo.getExecutionReportAndCache(
                cacheScope: cacheScope,
                serviceId: serviceId,
                technicianId: userId,
              );
      } on ApiException catch (e) {
        reportError = e.message;
      } catch (e) {
        reportError = e.toString();
      }

      try {
        checklistBundle = cacheScope.isEmpty
          ? await repo.getServiceChecklists(serviceId: serviceId)
          : await repo.getServiceChecklistsAndCache(
            cacheScope: cacheScope,
            serviceId: serviceId,
            );
        } on ApiException catch (e) {
        checklistError = e.message;
        } catch (e) {
        checklistError = e.toString();
        }

      final combinedError = [
        if ((reportError ?? '').trim().isNotEmpty) reportError!.trim(),
        if ((checklistError ?? '').trim().isNotEmpty) checklistError!.trim(),
      ].join('\n');

      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: combinedError.isEmpty ? null : combinedError,
        service: service,
        changes: bundle.changes,
        arrivedAt: arrivedAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
        notes: notes,
        clientApproved: clientApproved,
        checklistData: checklistData,
        phaseSpecificData: phaseSpecificData,
        dynamicChecklists: checklistBundle.templates,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: e.toString(),
      );
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

  void _markPendingFailed(String id) {
    final list = state.pendingEvidence;
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final cur = list[idx];
    final updated = [...list];
    updated[idx] = cur.copyWith(status: PendingEvidenceStatus.failed);
    state = state.copyWith(pendingEvidence: updated);
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
      'checklistData': state.checklistData,
      'phaseSpecificData': state.phaseSpecificData,
      'at': DateTime.now().toIso8601String(),
    });
  }

  void setChecklistItem(String key, bool value) {
    if (_readOnly) return;
    final k = key.trim();
    if (k.isEmpty) return;

    final next = <String, dynamic>{...state.checklistData};
    final items = <String, dynamic>{
      ...(next['items'] is Map
          ? (next['items'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{}),
    };
    items[k] = value;
    next['items'] = items;
    next['updatedAt'] = DateTime.now().toIso8601String();

    state = state.copyWith(checklistData: next);
    unawaited(_persistDraft());
    _debouncedSave();
  }

  Future<void> setDynamicChecklistItem(String itemId, bool value) async {
    if (_readOnly) return;

    final templates = state.dynamicChecklists;
    if (templates.isEmpty) {
      setChecklistItem(itemId, value);
      return;
    }

    final updatedTemplates = templates
        .map((template) {
          final items = template.items
              .map(
                (item) => item.id == itemId
                    ? item.copyWith(
                        isChecked: value,
                        checkedAt: value ? DateTime.now() : null,
                      )
                    : item,
              )
              .toList(growable: false);
          return template.copyWith(items: items);
        })
        .toList(growable: false);

    state = state.copyWith(
      dynamicChecklists: updatedTemplates,
      clearError: true,
    );

    try {
      final repo = ref.read(operationsRepositoryProvider);
      await repo.checkServiceChecklistItemOrQueue(
        scope: (ref.read(authStateProvider).user?.id ?? '').trim(),
        itemId: itemId,
        isChecked: value,
      );
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      await load();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      await load();
    }
  }

  bool checklistValue(String key) {
    final k = key.trim();
    if (k.isEmpty) return false;
    final rawItems = state.checklistData['items'];
    if (rawItems is Map) {
      final v = rawItems[k];
      return v == true;
    }
    return false;
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

  void markArrivedNow({bool captureGps = true}) {
    unawaited(_markArrivedNow(captureGps: captureGps));
  }

  Future<void> setArrivedAtNow({bool captureGps = false}) {
    return _markArrivedNow(captureGps: captureGps);
  }

  Future<void> _markArrivedNow({required bool captureGps}) async {
    if (_readOnly) return;
    state = state.copyWith(arrivedAt: DateTime.now());

    if (captureGps) {
      try {
        final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          throw Exception('Servicios de ubicación desactivados');
        }

        var permission = await geo.Geolocator.checkPermission();
        if (permission == geo.LocationPermission.denied) {
          permission = await geo.Geolocator.requestPermission();
        }
        if (permission == geo.LocationPermission.denied) {
          throw Exception('Permiso de ubicación denegado');
        }
        if (permission == geo.LocationPermission.deniedForever) {
          throw Exception('Permiso de ubicación denegado permanentemente');
        }

        final pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
          timeLimit: const Duration(seconds: 12),
        );

        if (!mounted) return;

        final next = <String, dynamic>{...state.phaseSpecificData};
        next['arrivalGps'] = {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'altitude': pos.altitude,
          'heading': pos.heading,
          'speed': pos.speed,
          'capturedAt': DateTime.now().toIso8601String(),
        };

        state = state.copyWith(phaseSpecificData: next);
      } catch (e) {
        // Do not block arrival timestamp.
        state = state.copyWith(error: 'GPS: $e');
      }
    }

    unawaited(_persistDraft());
    unawaited(saveNow());
  }

  void markStartedNow() {
    unawaited(setStartedAtNow());
  }

  Future<void> setStartedAtNow() async {
    if (_readOnly) return;
    state = state.copyWith(startedAt: DateTime.now());
    await _persistDraft();
    await saveNow();
  }

  void markFinishedNow() {
    unawaited(setFinishedAtNow());
  }

  Future<void> setFinishedAtNow() async {
    if (_readOnly) return;
    state = state.copyWith(finishedAt: DateTime.now());
    await _persistDraft();
    await saveNow();
  }

  void _debouncedSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(saveNow());
    });
  }

  Future<void> saveNow() async {
    if (_readOnly) return;
    if (state.savingReport) return;

    final service = state.service;
    if (service == null) return;
    final userId = (ref.read(authStateProvider).user?.id ?? '').trim();
    final technicianId = _resolveTechnicianId(service);
    if (technicianId.isEmpty) {
      state = state.copyWith(
        savingReport: false,
        error: 'Este servicio no tiene técnico asignado para guardar la firma.',
      );
      return;
    }

    state = state.copyWith(savingReport: true, clearError: true);

    try {
      final repo = ref.read(operationsRepositoryProvider);
      final queued = await repo.upsertExecutionReportOrQueue(
        scope: userId,
        serviceId: serviceId,
        technicianId: technicianId,
        phase: service.currentPhase,
        arrivedAt: state.arrivedAt,
        startedAt: state.startedAt,
        finishedAt: state.finishedAt,
        notes: state.notes,
        checklistData: state.checklistData.isEmpty ? null : state.checklistData,
        phaseSpecificData: _phaseSpecificDataForRemote(),
        clientApproved: state.clientApproved,
      );

      state = state.copyWith(
        savingReport: false,
        error: queued
            ? 'Reporte guardado localmente. Se sincronizará en segundo plano.'
            : null,
      );
      if (_shouldKeepDraftAfterSave()) {
        await _persistDraft();
      } else {
        await _clearDraft();
      }
    } on ApiException catch (e) {
      state = state.copyWith(savingReport: false, error: e.message);
    } catch (e) {
      state = state.copyWith(savingReport: false, error: e.toString());
    }
  }

  Future<void> changeOrderState({
    required String orderState,
    String? techStatus,
    String? message,
  }) async {
    if (_readOnly) return;
    if (state.savingUpdate) return;

    final service = state.service;
    if (service == null) return;

    final next = orderState.trim().toLowerCase();
    if (next.isEmpty) return;

    state = state.copyWith(savingUpdate: true, clearError: true);
    try {
      final repo = ref.read(operationsRepositoryProvider);
      await repo.changeOrderState(
        serviceId: serviceId,
        orderState: next,
        message: message,
      );

      // Nota: el backend ya registra `status_change` al cambiar el estado.
      // Evitamos crear updates extra con types no soportados.

      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      final refreshed = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );
      state = state.copyWith(savingUpdate: false, service: refreshed);

      _syncServiceLists(refreshed);

      // Keep the technician list hot and in sync.
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );

      // Reconcile other filters/dashboard soon.
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
    } on ApiException catch (e) {
      state = state.copyWith(savingUpdate: false, error: e.message);
    } catch (e) {
      state = state.copyWith(savingUpdate: false, error: e.toString());
    }
  }

  Future<void> setTechProgress(String progressKey) async {
    if (_readOnly) return;
    final key = progressKey.trim().toLowerCase();
    if (key.isEmpty) return;

    String mapToOrderState(String k) {
      switch (k) {
        case 'tecnico_en_camino':
          return 'en_camino';
        case 'tecnico_en_el_lugar':
        case 'instalacion_iniciada':
          return 'en_proceso';
        case 'instalacion_finalizada':
          return 'finalizada';
        default:
          return 'en_proceso';
      }
    }

    final now = DateTime.now();
    final nextPhase = <String, dynamic>{...state.phaseSpecificData};
    nextPhase['techProgress'] = key;
    nextPhase['techProgressAt'] = now.toIso8601String();

    final history = <Map<String, dynamic>>[];
    final rawHistory = nextPhase['techProgressHistory'];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is Map) {
          history.add(item.cast<String, dynamic>());
        }
      }
    }

    final lastState = history.isNotEmpty
        ? (history.last['state'] ?? '').toString().trim().toLowerCase()
        : '';
    if (lastState != key) {
      history.add({'state': key, 'at': now.toIso8601String()});
      nextPhase['techProgressHistory'] = history;
    }

    DateTime? arrivedAt = state.arrivedAt;
    DateTime? startedAt = state.startedAt;
    DateTime? finishedAt = state.finishedAt;

    if (key == 'tecnico_en_camino') {
      nextPhase['onTheWayAt'] =
          (nextPhase['onTheWayAt'] ?? now.toIso8601String());
    }
    if (key == 'tecnico_en_el_lugar' && arrivedAt == null) {
      arrivedAt = now;
    }
    if (key == 'instalacion_iniciada' && startedAt == null) {
      startedAt = now;
    }
    if (key == 'instalacion_finalizada' && finishedAt == null) {
      finishedAt = now;
    }

    state = state.copyWith(
      phaseSpecificData: nextPhase,
      arrivedAt: arrivedAt,
      startedAt: startedAt,
      finishedAt: finishedAt,
    );
    await _persistDraft();

    // Persist execution report + history. These are separate server endpoints.
    await saveNow();
    await changeOrderState(
      orderState: mapToOrderState(key),
      techStatus: key,
      message: 'Estado técnico actualizado',
    );
  }

  Future<void> setInvoicePaid(bool paid) async {
    if (_readOnly) return;
    if (state.savingUpdate) return;

    final service = state.service;
    if (service == null) return;

    state = state.copyWith(savingUpdate: true, clearError: true);
    try {
      final repo = ref.read(operationsRepositoryProvider);
      final msg = paid ? '[PAGO] estado=pagado' : '[PAGO] estado=pendiente';
      await repo.addUpdate(serviceId: serviceId, type: 'note', message: msg);

      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      final refreshed = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );
      state = state.copyWith(savingUpdate: false, service: refreshed);

      _syncServiceLists(refreshed);

      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
    } on ApiException catch (e) {
      state = state.copyWith(savingUpdate: false, error: e.message);
    } catch (e) {
      state = state.copyWith(savingUpdate: false, error: e.toString());
    }
  }

  Future<void> addInfoUpdate({
    required String kind,
    required String text,
  }) async {
    if (_readOnly) return;
    if (state.savingUpdate) return;

    final k = kind.trim().toLowerCase();
    final t = text.trim();
    if (k.isEmpty || t.isEmpty) return;

    final service = state.service;
    if (service == null) return;

    final seq = TraceLog.nextSeq();
    TraceLog.log(
      'OpsTech',
      'addInfoUpdate begin serviceId=$serviceId kind=$k len=${t.length}',
      seq: seq,
    );

    final now = DateTime.now();
    final userName = (ref.read(authStateProvider).user?.nombreCompleto ?? '')
        .trim();
    final optimisticId = 'local_${now.microsecondsSinceEpoch}';
    final optimistic = ServiceUpdateModel(
      id: optimisticId,
      type: 'note',
      message: 'kind=$k|text=$t',
      changedBy: userName.isEmpty ? 'Técnico' : userName,
      createdAt: now,
    );

    // Optimistic UI update so the info shows immediately in the screen.
    state = state.copyWith(
      savingUpdate: true,
      clearError: true,
      service: service.copyWith(updates: [...service.updates, optimistic]),
    );
    try {
      final repo = ref.read(operationsRepositoryProvider);
      await repo.addUpdate(
        serviceId: serviceId,
        type: 'note',
        message: 'kind=$k|text=$t',
      );
      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      final refreshed = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );
      state = state.copyWith(savingUpdate: false, service: refreshed);
      _syncServiceLists(refreshed);
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );

      TraceLog.log('OpsTech', 'addInfoUpdate done', seq: seq);
    } on ApiException catch (e) {
      final cur = state.service;
      if (cur != null) {
        state = state.copyWith(
          savingUpdate: false,
          error: e.message,
          service: cur.copyWith(
            updates: cur.updates.where((u) => u.id != optimisticId).toList(),
          ),
        );
      } else {
        state = state.copyWith(savingUpdate: false, error: e.message);
      }

      TraceLog.log('OpsTech', 'addInfoUpdate failed', seq: seq, error: e);
      rethrow;
    } catch (e) {
      final cur = state.service;
      if (cur != null) {
        state = state.copyWith(
          savingUpdate: false,
          error: e.toString(),
          service: cur.copyWith(
            updates: cur.updates.where((u) => u.id != optimisticId).toList(),
          ),
        );
      } else {
        state = state.copyWith(savingUpdate: false, error: e.toString());
      }

      TraceLog.log('OpsTech', 'addInfoUpdate failed', seq: seq, error: e);
      rethrow;
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

      final updatedService = service.copyWith(steps: updatedSteps);
      state = state.copyWith(service: updatedService);
      _syncServiceLists(updatedService);
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );
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
    final kind = isVideo ? 'video_evidence' : 'evidence_final';

    final seq = TraceLog.nextSeq();
    TraceLog.log(
      'OpsTech',
      'uploadEvidence begin serviceId=$serviceId kind=$kind name=${file.name} size=${file.size}',
      seq: seq,
    );

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
      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      final refreshed = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );

      if (!mounted) return;
      _removePending(id);
      state = state.copyWith(service: refreshed);
      _syncServiceLists(refreshed);
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );

      TraceLog.log('OpsTech', 'uploadEvidence done', seq: seq);
    } catch (e) {
      if (!mounted) return;
      _markPendingFailed(id);
      if (e is ApiException) {
        state = state.copyWith(error: e.message);
        TraceLog.log('OpsTech', 'uploadEvidence failed', seq: seq, error: e);
        rethrow;
      } else {
        state = state.copyWith(error: e.toString());
        TraceLog.log('OpsTech', 'uploadEvidence failed', seq: seq, error: e);
        rethrow;
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

      final seq = TraceLog.nextSeq();
      TraceLog.log(
        'OpsTech',
        'uploadEvidenceXFile begin serviceId=$serviceId kind=$kind name=${file.name} size=$size web=$kIsWeb',
        seq: seq,
      );

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
      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      final refreshed = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );

      if (!mounted) return;
      _removePending(id);
      state = state.copyWith(service: refreshed);
      _syncServiceLists(refreshed);
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );

      TraceLog.log('OpsTech', 'uploadEvidenceXFile done', seq: seq);
    } catch (e) {
      if (!mounted) return;
      _markPendingFailed(id);
      if (e is ApiException) {
        state = state.copyWith(error: e.message);
        rethrow;
      } else {
        state = state.copyWith(error: e.toString());
        rethrow;
      }
    }
  }

  Future<void> saveClientSignatureLocally({required Uint8List pngBytes}) async {
    if (_readOnly) return;
    final service = state.service;
    if (service == null) return;

    final signedAtIso = DateTime.now().toIso8601String();
    final signatureBase64 = base64Encode(pngBytes);
    _setClientSignatureMeta({
      'signedAt': signedAtIso,
      'syncStatus': _signatureSyncLocalSaved,
      'localPreviewBase64': signatureBase64,
    });
    await _persistDraft();
    TraceLog.log('OpsTech', 'Signature saved locally serviceId=$serviceId');
    unawaited(
      _uploadClientSignatureInBackground(
        signatureBase64: signatureBase64,
        signedAtIso: signedAtIso,
      ),
    );
  }

  Future<void> _uploadClientSignatureInBackground({
    required String signatureBase64,
    required String signedAtIso,
  }) async {
    if (_readOnly || !mounted) return;

    _setClientSignatureMeta({
      'signedAt': signedAtIso,
      'syncStatus': _signatureSyncUploading,
      'localPreviewBase64': signatureBase64,
    });
    unawaited(_persistDraft());
    TraceLog.log('OpsTech', 'Uploading signature serviceId=$serviceId');

    final userId = (ref.read(authStateProvider).user?.id ?? '').trim();
    final repo = ref.read(operationsRepositoryProvider);
    final fileName =
        'firma-cliente-${DateTime.now().millisecondsSinceEpoch}.png';

    try {
      final result = await repo.uploadServiceSignatureOrQueue(
        scope: userId,
        serviceId: serviceId,
        signatureBase64: signatureBase64,
        signedAtIso: signedAtIso,
        fileName: fileName,
        mimeType: 'image/png',
      );

      if (!mounted) return;

      if (result == null) {
        _setClientSignatureMeta({
          'signedAt': signedAtIso,
          'syncStatus': _signatureSyncPendingUpload,
          'localPreviewBase64': signatureBase64,
        });
        unawaited(_persistDraft());
        TraceLog.log(
          'OpsTech',
          'Upload failed serviceId=$serviceId queued_retry=true',
        );
        return;
      }

      _setClientSignatureMeta({
        if (result.fileId != null) 'fileId': result.fileId,
        if (result.fileUrl != null) 'fileUrl': result.fileUrl,
        'signedAt': (result.signedAt ?? DateTime.parse(signedAtIso))
            .toIso8601String(),
        'syncStatus': _signatureSyncCompleted,
      });
      await _persistDraft();
      TraceLog.log('OpsTech', 'Upload success serviceId=$serviceId');

      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      final refreshed = cacheScope.isEmpty
          ? await repo.getService(serviceId)
          : await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );

      if (!mounted) return;
      state = state.copyWith(service: refreshed);
      _syncServiceLists(refreshed);
      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );
      unawaited(saveNow());
    } on ApiException catch (e) {
      if (!mounted) return;
      _setClientSignatureMeta({
        'signedAt': signedAtIso,
        'syncStatus': _signatureSyncPendingUpload,
        'localPreviewBase64': signatureBase64,
        'syncError': e.message,
      });
      unawaited(_persistDraft());
      TraceLog.log('OpsTech', 'Upload failed serviceId=$serviceId', error: e);
    } catch (e) {
      if (!mounted) return;
      _setClientSignatureMeta({
        'signedAt': signedAtIso,
        'syncStatus': _signatureSyncPendingUpload,
        'localPreviewBase64': signatureBase64,
        'syncError': e.toString(),
      });
      unawaited(_persistDraft());
      TraceLog.log('OpsTech', 'Upload failed serviceId=$serviceId', error: e);
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

      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      if (cacheScope.isNotEmpty) {
        unawaited(() async {
          try {
            final refreshed = await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );
            if (!mounted) return;
            state = state.copyWith(service: refreshed);
            _syncServiceLists(refreshed);
          } catch (_) {
            // ignore
          }
        }());
      }

      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );
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

      final cacheScope = (ref.read(authStateProvider).user?.id ?? '').trim();
      if (cacheScope.isNotEmpty) {
        unawaited(() async {
          try {
            final refreshed = await repo.getServiceAndCache(
              cacheScope: cacheScope,
              id: serviceId,
              silent: true,
            );
            if (!mounted) return;
            state = state.copyWith(service: refreshed);
            _syncServiceLists(refreshed);
          } catch (_) {
            // ignore
          }
        }());
      }

      unawaited(ref.read(operationsControllerProvider.notifier).refresh());
      unawaited(
        ref
            .read(techOperationsControllerProvider.notifier)
            .refresh(silent: true),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}
