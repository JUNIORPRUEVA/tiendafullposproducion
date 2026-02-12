import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/punch_model.dart';
import '../data/punch_repository.dart';
import '../models/attendance_models.dart';

class PunchState {
  final List<PunchModel> items;
  final bool loading;
  final bool creating;
  final String? error;

  const PunchState({
    this.items = const [],
    this.loading = false,
    this.creating = false,
    this.error,
  });

  PunchState copyWith({
    List<PunchModel>? items,
    bool? loading,
    bool? creating,
    String? error,
    bool clearError = false,
  }) {
    return PunchState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      creating: creating ?? this.creating,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final punchControllerProvider = StateNotifierProvider.autoDispose<PunchController, PunchState>((ref) {
  // Recreate/clear state when el usuario cambia para no mostrar ponches de otra sesión.
  ref.watch(authStateProvider);
  return PunchController(ref);
});

class PunchController extends StateNotifier<PunchState> {
  final Ref ref;

  PunchController(this.ref) : super(const PunchState()) {
    load();
  }

  Future<void> load({DateTime? from, DateTime? to}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(punchRepositoryProvider);
      final items = await repo.listMine(from: from, to: to);
      state = state.copyWith(items: items, loading: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo cargar el historial';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<PunchModel> register(PunchType type) async {
    state = state.copyWith(creating: true, clearError: true);
    try {
      final repo = ref.read(punchRepositoryProvider);
      final punch = await repo.createPunch(type);
      state = state.copyWith(
        creating: false,
        items: [punch, ...state.items],
      );
      return punch;
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo registrar el ponche';
      state = state.copyWith(creating: false, error: message);
      throw ApiException(message);
    }
  }
}

enum AttendanceFilterOption { today, yesterday, range }

class AttendanceDashboardState {
  final AttendanceSummaryModel? summary;
  final bool loading;
  final String? error;
  final AttendanceFilterOption filterOption;
  final DateTime? customFrom;
  final DateTime? customTo;
  final String? selectedUserId;
  final bool incidentsOnly;
  final AttendanceDetailModel? detail;
  final bool detailLoading;
  final String? detailError;
  final String? detailUserId;

  const AttendanceDashboardState({
    this.summary,
    this.loading = false,
    this.error,
    this.filterOption = AttendanceFilterOption.today,
    this.customFrom,
    this.customTo,
    this.selectedUserId,
    this.incidentsOnly = false,
    this.detail,
    this.detailLoading = false,
    this.detailError,
    this.detailUserId,
  });

  AttendanceDashboardState copyWith({
    AttendanceSummaryModel? summary,
    bool? loading,
    String? error,
    bool clearError = false,
    bool clearSummary = false,
    AttendanceFilterOption? filterOption,
    DateTime? customFrom,
    DateTime? customTo,
    String? selectedUserId,
    bool? incidentsOnly,
    AttendanceDetailModel? detail,
    bool? detailLoading,
    String? detailError,
    bool clearDetailError = false,
    bool clearDetail = false,
    String? detailUserId,
  }) {
    return AttendanceDashboardState(
      summary: clearSummary ? null : (summary ?? this.summary),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      filterOption: filterOption ?? this.filterOption,
      customFrom: customFrom ?? this.customFrom,
      customTo: customTo ?? this.customTo,
      selectedUserId: selectedUserId ?? this.selectedUserId,
      incidentsOnly: incidentsOnly ?? this.incidentsOnly,
      detail: clearDetail ? null : (detail ?? this.detail),
      detailLoading: detailLoading ?? this.detailLoading,
      detailError: clearDetailError ? null : (detailError ?? this.detailError),
      detailUserId: detailUserId ?? this.detailUserId,
    );
  }

  factory AttendanceDashboardState.initial() => const AttendanceDashboardState();
}

final attendanceDashboardControllerProvider = StateNotifierProvider.autoDispose<AttendanceDashboardController, AttendanceDashboardState>((ref) {
  // Recalcular datos administrativos al cambiar de usuario/sesión.
  ref.watch(authStateProvider);
  return AttendanceDashboardController(ref);
});

class AttendanceDashboardController extends StateNotifier<AttendanceDashboardState> {
  final Ref ref;

  AttendanceDashboardController(this.ref) : super(AttendanceDashboardState.initial()) {
    _loadSummary();
  }

  Future<void> applyFilters({
    AttendanceFilterOption? filterOption,
    DateTime? customFrom,
    DateTime? customTo,
    String? selectedUserId,
    bool? incidentsOnly,
  }) async {
    final nextFilter = filterOption ?? state.filterOption;
    final normalizedUser = _normalizeUser(selectedUserId ?? state.selectedUserId);
    final nextFrom = nextFilter == AttendanceFilterOption.range ? customFrom ?? state.customFrom : null;
    final nextTo = nextFilter == AttendanceFilterOption.range ? customTo ?? state.customTo : null;

    state = state.copyWith(
      filterOption: nextFilter,
      customFrom: nextFrom,
      customTo: nextTo,
      selectedUserId: normalizedUser,
      incidentsOnly: incidentsOnly ?? state.incidentsOnly,
      clearError: true,
      clearSummary: true,
      clearDetail: true,
      clearDetailError: true,
      detailUserId: null,
    );

    await _loadSummary();
  }

  Future<void> refresh() async => _loadSummary();

  Future<void> loadDetail(String userId) async {
    state = state.copyWith(
      detailLoading: true,
      detailError: null,
      detail: null,
      detailUserId: userId,
    );

    try {
      final detail = await ref.read(punchRepositoryProvider).fetchAttendanceDetail(
            userId,
            from: _resolvedFrom,
            to: _resolvedTo,
          );
      state = state.copyWith(detailLoading: false, detail: detail, clearDetailError: true);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo cargar el detalle';
      state = state.copyWith(detailLoading: false, detailError: message, clearDetail: true);
    }
  }

  void clearDetail() {
    state = state.copyWith(clearDetail: true, clearDetailError: true, detailUserId: null);
  }

  DateTime? get _resolvedFrom {
    final now = DateTime.now();
    switch (state.filterOption) {
      case AttendanceFilterOption.today:
        return DateTime(now.year, now.month, now.day);
      case AttendanceFilterOption.yesterday:
        final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
        return yesterday;
      case AttendanceFilterOption.range:
        return state.customFrom;
    }
  }

  DateTime? get _resolvedTo {
    switch (state.filterOption) {
      case AttendanceFilterOption.range:
        return state.customTo;
      case AttendanceFilterOption.today:
      case AttendanceFilterOption.yesterday:
        return _resolvedFrom;
    }
  }

  Future<void> _loadSummary() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final summary = await ref.read(punchRepositoryProvider).fetchAttendanceSummary(
            from: _resolvedFrom,
            to: _resolvedTo,
            userId: state.selectedUserId,
            incidentsOnly: state.incidentsOnly,
          );
      state = state.copyWith(loading: false, summary: summary);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudo cargar el dashboard de asistencia';
      state = state.copyWith(loading: false, error: message);
    }
  }

  String? _normalizeUser(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class AdminPunchState {
  final List<PunchModel> items;
  final bool loading;
  final String? error;
  final DateTime? from;
  final DateTime? to;
  final String? userId;

  const AdminPunchState({
    this.items = const [],
    this.loading = false,
    this.error,
    this.from,
    this.to,
    this.userId,
  });

  AdminPunchState copyWith({
    List<PunchModel>? items,
    bool? loading,
    String? error,
    bool clearError = false,
    DateTime? from,
    DateTime? to,
    String? userId,
  }) {
    return AdminPunchState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      from: from ?? this.from,
      to: to ?? this.to,
      userId: userId ?? this.userId,
    );
  }
}

final adminPunchControllerProvider = StateNotifierProvider.autoDispose<AdminPunchController, AdminPunchState>((ref) {
  // Evita que datos de otra sesión persistan en el panel admin.
  ref.watch(authStateProvider);
  return AdminPunchController(ref);
});

class AdminPunchController extends StateNotifier<AdminPunchState> {
  final Ref ref;

  AdminPunchController(this.ref) : super(const AdminPunchState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(punchRepositoryProvider);
      final items = await repo.listAdmin(userId: state.userId, from: state.from, to: state.to);
      state = state.copyWith(items: items, loading: false);
    } catch (e) {
      final message = e is ApiException ? e.message : 'No se pudieron cargar los ponches';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> applyFilters({String? userId, DateTime? from, DateTime? to}) async {
    state = state.copyWith(userId: userId, from: from, to: to);
    await refresh();
  }

  Future<void> clearFilters() async {
    state = state.copyWith(userId: null, from: null, to: null);
    await refresh();
  }
}
