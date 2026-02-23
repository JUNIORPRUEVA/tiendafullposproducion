import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/nomina_repository.dart';
import '../nomina_models.dart';

class NominaHomeState {
  final bool loading;
  final String? error;
  final List<PayrollPeriod> periods;

  const NominaHomeState({
    this.loading = false,
    this.error,
    this.periods = const [],
  });

  PayrollPeriod? get openPeriod {
    for (final period in periods) {
      if (period.isOpen) return period;
    }
    return null;
  }

  NominaHomeState copyWith({
    bool? loading,
    String? error,
    List<PayrollPeriod>? periods,
    bool clearError = false,
  }) {
    return NominaHomeState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      periods: periods ?? this.periods,
    );
  }
}

final nominaHomeControllerProvider =
    StateNotifierProvider<NominaHomeController, NominaHomeState>((ref) {
      return NominaHomeController(ref);
    });

class NominaHomeController extends StateNotifier<NominaHomeState> {
  NominaHomeController(this.ref) : super(const NominaHomeState()) {
    load();
  }

  final Ref ref;

  NominaRepository get _repo => ref.read(nominaRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final periods = await _repo.listPeriods();
      state = state.copyWith(loading: false, periods: periods);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo cargar nómina: $e',
      );
    }
  }

  Future<PayrollPeriod?> createPeriod({
    required DateTime start,
    required DateTime end,
    required String title,
  }) async {
    if (end.isBefore(start)) {
      throw Exception('La fecha final no puede ser menor que la inicial');
    }

    final overlaps = await _repo.hasOverlappingOpenPeriod(start, end);
    if (overlaps) {
      throw Exception('Ya existe una quincena abierta que se solapa con esas fechas.');
    }

    final period = await _repo.createPeriod(start, end, title);
    await load();
    return period;
  }

  Future<void> closePeriod(String periodId) async {
    await _repo.closePeriod(periodId);
    await load();
  }
}
