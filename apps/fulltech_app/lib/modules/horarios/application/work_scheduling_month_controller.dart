import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/work_scheduling_repository.dart';
import '../horarios_models.dart';
import 'work_scheduling_week_controller.dart';

class WorkSchedulingMonthState {
  final DateTime month;
  final bool loading;
  final String? error;
  final Map<String, WorkDayAssignment> byDateAndUser; // key: YYYY-MM-DD|userId

  const WorkSchedulingMonthState({
    required this.month,
    required this.loading,
    required this.error,
    required this.byDateAndUser,
  });

  factory WorkSchedulingMonthState.initial() {
    final now = DateTime.now();
    return WorkSchedulingMonthState(
      month: DateTime(now.year, now.month, 1),
      loading: false,
      error: null,
      byDateAndUser: const {},
    );
  }

  WorkSchedulingMonthState copyWith({
    DateTime? month,
    bool? loading,
    String? error,
    bool clearError = false,
    Map<String, WorkDayAssignment>? byDateAndUser,
  }) {
    return WorkSchedulingMonthState(
      month: month ?? this.month,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      byDateAndUser: byDateAndUser ?? this.byDateAndUser,
    );
  }
}

final workSchedulingMonthControllerProvider =
    StateNotifierProvider.autoDispose<
      WorkSchedulingMonthController,
      WorkSchedulingMonthState
    >((ref) => WorkSchedulingMonthController(ref));

class WorkSchedulingMonthController
    extends StateNotifier<WorkSchedulingMonthState> {
  final Ref ref;
  int _seq = 0;

  WorkSchedulingMonthController(this.ref)
    : super(WorkSchedulingMonthState.initial()) {
    load();
  }

  Future<void> setMonth(DateTime month) async {
    final m = DateTime(month.year, month.month, 1);
    state = state.copyWith(month: m);
    await load();
  }

  Future<void> prevMonth() =>
      setMonth(DateTime(state.month.year, state.month.month - 1, 1));

  Future<void> nextMonth() =>
      setMonth(DateTime(state.month.year, state.month.month + 1, 1));

  Future<void> load() async {
    final seq = ++_seq;
    state = state.copyWith(loading: true, clearError: true);

    try {
      final repo = ref.read(workSchedulingRepositoryProvider);
      final monthStart = DateTime(state.month.year, state.month.month, 1);
      final monthEnd = DateTime(state.month.year, state.month.month + 1, 0);

      final firstWeekStart = startOfWeekMonday(monthStart);
      final lastWeekStart = startOfWeekMonday(monthEnd);

      final weekStarts = <DateTime>[];
      for (
        var d = firstWeekStart;
        !d.isAfter(lastWeekStart);
        d = d.add(const Duration(days: 7))
      ) {
        weekStarts.add(d);
      }

      final next = <String, WorkDayAssignment>{};
      for (final ws in weekStarts) {
        final week = await repo.getWeek(dateOnly(ws));
        if (week == null) {
          if (seq != _seq) return;
          continue;
        }
        for (final a in week.days) {
          final key = '${a.date}|${a.userId}';
          next[key] = a;
        }
        if (seq != _seq) return;
      }

      state = state.copyWith(loading: false, byDateAndUser: next);
    } catch (e) {
      if (seq != _seq) return;
      state = state.copyWith(loading: false, error: '$e');
    }
  }
}
