import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/errors/api_exception.dart';
import '../data/operations_repository.dart';
import '../operations_models.dart';
import '../presentation/operations_permissions.dart';

class TechnicalExecutionState {
  final bool loading;
  final bool saving;
  final String? error;
  final ServiceModel? service;
  final List<ServiceExecutionChangeModel> changes;

  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String notes;
  final bool clientApproved;

  const TechnicalExecutionState({
    this.loading = false,
    this.saving = false,
    this.error,
    this.service,
    this.changes = const [],
    this.arrivedAt,
    this.startedAt,
    this.finishedAt,
    this.notes = '',
    this.clientApproved = false,
  });

  bool get hasService => service != null && service!.id.trim().isNotEmpty;

  TechnicalExecutionState copyWith({
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
    ServiceModel? service,
    List<ServiceExecutionChangeModel>? changes,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? notes,
    bool? clientApproved,
  }) {
    return TechnicalExecutionState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      service: service ?? this.service,
      changes: changes ?? this.changes,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      notes: notes ?? this.notes,
      clientApproved: clientApproved ?? this.clientApproved,
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
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
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
      'at': DateTime.now().toIso8601String(),
    });
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

  Future<void> uploadEvidence() async {
    if (_readOnly) return;
    final service = state.service;
    if (service == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
      final file = result?.files.isNotEmpty == true
          ? result!.files.first
          : null;
      if (file == null) return;

      final repo = ref.read(operationsRepositoryProvider);
      await repo.uploadEvidence(serviceId: serviceId, file: file);

      final refreshed = await repo.getService(serviceId);
      state = state.copyWith(service: refreshed);
    } catch (e) {
      state = state.copyWith(error: e.toString());
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
