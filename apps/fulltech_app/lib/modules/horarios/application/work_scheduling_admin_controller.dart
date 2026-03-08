import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/work_scheduling_repository.dart';
import '../horarios_models.dart';

class WorkSchedulingAdminState {
  final bool loading;
  final String? error;

  final List<WorkEmployee> employees;
  final List<WorkScheduleProfile> profiles;
  final List<WorkCoverageRule> coverageRules;
  final List<WorkScheduleException> exceptions;

  final DateTime from;
  final DateTime to;
  final List<WorkScheduleAuditLog> audit;
  final List<Map<String, dynamic>> reportMostChanges;
  final List<Map<String, dynamic>> reportLowCoverage;

  const WorkSchedulingAdminState({
    required this.loading,
    required this.error,
    required this.employees,
    required this.profiles,
    required this.coverageRules,
    required this.exceptions,
    required this.from,
    required this.to,
    required this.audit,
    required this.reportMostChanges,
    required this.reportLowCoverage,
  });

  factory WorkSchedulingAdminState.initial() {
    final now = DateTime.now();
    return WorkSchedulingAdminState(
      loading: false,
      error: null,
      employees: const [],
      profiles: const [],
      coverageRules: const [],
      exceptions: const [],
      from: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30)),
      to: DateTime(now.year, now.month, now.day),
      audit: const [],
      reportMostChanges: const [],
      reportLowCoverage: const [],
    );
  }

  WorkSchedulingAdminState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<WorkEmployee>? employees,
    List<WorkScheduleProfile>? profiles,
    List<WorkCoverageRule>? coverageRules,
    List<WorkScheduleException>? exceptions,
    DateTime? from,
    DateTime? to,
    List<WorkScheduleAuditLog>? audit,
    List<Map<String, dynamic>>? reportMostChanges,
    List<Map<String, dynamic>>? reportLowCoverage,
  }) {
    return WorkSchedulingAdminState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      employees: employees ?? this.employees,
      profiles: profiles ?? this.profiles,
      coverageRules: coverageRules ?? this.coverageRules,
      exceptions: exceptions ?? this.exceptions,
      from: from ?? this.from,
      to: to ?? this.to,
      audit: audit ?? this.audit,
      reportMostChanges: reportMostChanges ?? this.reportMostChanges,
      reportLowCoverage: reportLowCoverage ?? this.reportLowCoverage,
    );
  }
}

final workSchedulingAdminControllerProvider = StateNotifierProvider<
    WorkSchedulingAdminController, WorkSchedulingAdminState>((ref) {
  return WorkSchedulingAdminController(ref);
});

class WorkSchedulingAdminController
    extends StateNotifier<WorkSchedulingAdminState> {
  final Ref ref;
  int _loadSeq = 0;

  WorkSchedulingAdminController(this.ref)
      : super(WorkSchedulingAdminState.initial());

  Future<void> loadBasics() async {
    final seq = ++_loadSeq;
    state = state.copyWith(loading: true, clearError: true);

    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final results = await Future.wait([
        repo.listEmployees(),
        repo.listProfiles(),
        repo.listCoverageRules(),
      ]);

      if (seq != _loadSeq) return;
      state = state.copyWith(
        loading: false,
        employees: results[0] as List<WorkEmployee>,
        profiles: results[1] as List<WorkScheduleProfile>,
        coverageRules: results[2] as List<WorkCoverageRule>,
      );
    } catch (e) {
      if (seq != _loadSeq) return;
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> loadExceptionsForWeek(String weekStartDate) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final items = await repo.listExceptions(weekStartDate: weekStartDate);
      state = state.copyWith(loading: false, exceptions: items);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> saveEmployeeConfig(
    String userId, {
    bool? enabled,
    String? scheduleProfileId,
    int? preferredDayOffWeekday,
    int? fixedDayOffWeekday,
    List<int>? disallowedDayOffWeekdays,
    List<int>? unavailableWeekdays,
    String? notes,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      await repo.updateEmployeeConfig(
        userId,
        enabled: enabled,
        scheduleProfileId: scheduleProfileId,
        preferredDayOffWeekday: preferredDayOffWeekday,
        fixedDayOffWeekday: fixedDayOffWeekday,
        disallowedDayOffWeekdays: disallowedDayOffWeekdays,
        unavailableWeekdays: unavailableWeekdays,
        notes: notes,
      );
      final employees = await repo.listEmployees();
      state = state.copyWith(loading: false, employees: employees);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> saveCoverageRules(List<WorkCoverageRule> rules) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      await repo.upsertCoverageRules(rules);
      final refreshed = await repo.listCoverageRules();
      state = state.copyWith(loading: false, coverageRules: refreshed);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> loadAuditAndReports() async {
    state = state.copyWith(loading: true, clearError: true);

    final fromIso = dateOnly(state.from);
    final toIso = dateOnly(state.to);

    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final results = await Future.wait([
        repo.listAudit(from: fromIso, to: toIso),
        repo.reportMostChanges(from: fromIso, to: toIso),
        repo.reportLowCoverage(from: fromIso, to: toIso),
      ]);

      state = state.copyWith(
        loading: false,
        audit: results[0] as List<WorkScheduleAuditLog>,
        reportMostChanges: results[1] as List<Map<String, dynamic>>,
        reportLowCoverage: results[2] as List<Map<String, dynamic>>,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  void setRange({DateTime? from, DateTime? to}) {
    state = state.copyWith(
      from: from ?? state.from,
      to: to ?? state.to,
    );
  }
}
