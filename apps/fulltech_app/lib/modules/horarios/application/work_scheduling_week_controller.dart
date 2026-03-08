import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/work_scheduling_repository.dart';
import '../horarios_models.dart';

DateTime startOfWeekMonday(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final weekday = d.weekday; // 1=Mon..7=Sun
  final delta = weekday - DateTime.monday;
  return d.subtract(Duration(days: delta));
}

class WorkSchedulingWeekState {
  final DateTime weekStart;
  final bool loading;
  final String? error;
  final WorkWeekSchedule? week;

  const WorkSchedulingWeekState({
    required this.weekStart,
    required this.loading,
    required this.error,
    required this.week,
  });

  factory WorkSchedulingWeekState.initial() {
    final now = DateTime.now();
    return WorkSchedulingWeekState(
      weekStart: startOfWeekMonday(now),
      loading: false,
      error: null,
      week: null,
    );
  }

  WorkSchedulingWeekState copyWith({
    DateTime? weekStart,
    bool? loading,
    String? error,
    bool clearError = false,
    WorkWeekSchedule? week,
  }) {
    return WorkSchedulingWeekState(
      weekStart: weekStart ?? this.weekStart,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      week: week ?? this.week,
    );
  }
}

final workSchedulingWeekControllerProvider =
    StateNotifierProvider<WorkSchedulingWeekController, WorkSchedulingWeekState>(
  (ref) => WorkSchedulingWeekController(ref),
);

class WorkSchedulingWeekController extends StateNotifier<WorkSchedulingWeekState> {
  final Ref ref;
  int _loadSeq = 0;

  WorkSchedulingWeekController(this.ref)
      : super(WorkSchedulingWeekState.initial()) {
    load();
  }

  String get _weekStartIso => dateOnly(state.weekStart);

  Future<void> load({DateTime? weekStart}) async {
    final seq = ++_loadSeq;
    if (weekStart != null) {
      state = state.copyWith(weekStart: startOfWeekMonday(weekStart));
    }

    state = state.copyWith(loading: true, clearError: true);

    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final week = await repo.getWeek(_weekStartIso);
      if (seq != _loadSeq) return;
      state = state.copyWith(loading: false, week: week);
    } catch (e) {
      if (seq != _loadSeq) return;
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> prevWeek() =>
      load(weekStart: state.weekStart.subtract(const Duration(days: 7)));

  Future<void> nextWeek() =>
      load(weekStart: state.weekStart.add(const Duration(days: 7)));

  Future<void> generateWeek({String mode = 'REPLACE', String? note}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final week = await repo.generateWeek(
        weekStartDate: _weekStartIso,
        mode: mode,
        note: note,
      );
      state = state.copyWith(loading: false, week: week);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> manualMoveDayOff({
    required String userId,
    required String fromDate,
    required String toDate,
    required String reason,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final week = await repo.manualMoveDayOff(
        weekStartDate: _weekStartIso,
        userId: userId,
        fromDate: fromDate,
        toDate: toDate,
        reason: reason,
      );
      state = state.copyWith(loading: false, week: week);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> manualSwapDayOff({
    required String userAId,
    required String userADayOffDate,
    required String userBId,
    required String userBDayOffDate,
    required String reason,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final week = await repo.manualSwapDayOff(
        weekStartDate: _weekStartIso,
        userAId: userAId,
        userADayOffDate: userADayOffDate,
        userBId: userBId,
        userBDayOffDate: userBDayOffDate,
        reason: reason,
      );
      state = state.copyWith(loading: false, week: week);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }
}
