import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/close_model.dart';
import '../data/contabilidad_repository.dart';

enum CierresRangePreset { today, quincena, custom }

class CierresDateRange {
  final DateTime from;
  final DateTime to;

  const CierresDateRange({required this.from, required this.to});
}

class CierresDiariosState {
  final bool loading;
  final bool saving;
  final String? deletingId;
  final String? error;
  final List<CloseModel> closes;
  final DateTime from;
  final DateTime to;
  final CierresRangePreset preset;
  final CloseType? typeFilter;
  final CloseModel? editingClose;

  const CierresDiariosState({
    this.loading = false,
    this.saving = false,
    this.deletingId,
    this.error,
    this.closes = const [],
    required this.from,
    required this.to,
    required this.preset,
    this.typeFilter,
    this.editingClose,
  });

  factory CierresDiariosState.initial() {
    final now = DateTime.now();
    final range = _currentQuincena(now);
    return CierresDiariosState(
      from: range.from,
      to: range.to,
      preset: CierresRangePreset.quincena,
      typeFilter: CloseType.capsulas,
    );
  }

  CierresDiariosState copyWith({
    bool? loading,
    bool? saving,
    String? deletingId,
    String? error,
    List<CloseModel>? closes,
    DateTime? from,
    DateTime? to,
    CierresRangePreset? preset,
    CloseType? typeFilter,
    CloseModel? editingClose,
    bool clearError = false,
    bool clearDeleting = false,
    bool clearTypeFilter = false,
    bool clearEditing = false,
  }) {
    return CierresDiariosState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      deletingId: clearDeleting ? null : (deletingId ?? this.deletingId),
      error: clearError ? null : (error ?? this.error),
      closes: closes ?? this.closes,
      from: from ?? this.from,
      to: to ?? this.to,
      preset: preset ?? this.preset,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      editingClose: clearEditing ? null : (editingClose ?? this.editingClose),
    );
  }
}

final cierresDiariosControllerProvider =
    StateNotifierProvider<CierresDiariosController, CierresDiariosState>((ref) {
  return CierresDiariosController(ref);
});

class CierresDiariosController extends StateNotifier<CierresDiariosState> {
  final Ref ref;

  CierresDiariosController(this.ref) : super(CierresDiariosState.initial()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rows = await ref.read(contabilidadRepositoryProvider).listCloses(
            from: state.from,
            to: state.to,
        type: null,
          );

      state = state.copyWith(loading: false, closes: rows);
    } catch (e) {
      final message =
          e is ApiException ? e.message : 'No se pudieron cargar los cierres';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> refresh() => load();

  Future<void> setTypeFilter(CloseType type) async {
    state = state.copyWith(typeFilter: type, clearError: true);
  }

  Future<void> setPreset(CierresRangePreset preset) async {
    final now = DateTime.now();
    CierresDateRange range;

    switch (preset) {
      case CierresRangePreset.today:
        final day = DateTime(now.year, now.month, now.day);
        range = CierresDateRange(from: day, to: day);
        break;
      case CierresRangePreset.quincena:
        range = _currentQuincena(now);
        break;
      case CierresRangePreset.custom:
        return;
    }

    state = state.copyWith(
      preset: preset,
      from: range.from,
      to: range.to,
    );
    await load();
  }

  Future<void> setCustomRange(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return;

    state = state.copyWith(
      from: start,
      to: end,
      preset: CierresRangePreset.custom,
    );
    await load();
  }

  void startEditing(CloseModel close) {
    state = state.copyWith(editingClose: close, clearError: true);
  }

  void cancelEditing() {
    state = state.copyWith(clearEditing: true, clearError: true);
  }

  Future<void> saveClose({
    required CloseType type,
    required DateTime date,
    required double cash,
    required double transfer,
    String? transferBank,
    required double card,
    required double expenses,
    required double cashDelivered,
  }) async {
    state = state.copyWith(saving: true, clearError: true);

    try {
      final editing = state.editingClose;
      if (editing == null) {
        await ref.read(contabilidadRepositoryProvider).createClose(
              type: type,
              date: date,
              cash: cash,
              transfer: transfer,
              transferBank: transferBank,
              card: card,
              expenses: expenses,
              cashDelivered: cashDelivered,
              status: 'closed',
            );
      } else {
        await ref.read(contabilidadRepositoryProvider).updateClose(
              id: editing.id,
              cash: cash,
              transfer: transfer,
              transferBank: transferBank,
              card: card,
              expenses: expenses,
              cashDelivered: cashDelivered,
              status: 'closed',
            );
      }

      state = state.copyWith(
        saving: false,
        clearEditing: true,
      );
      await load();
    } catch (e) {
      final message =
          e is ApiException ? e.message : 'No se pudo guardar el cierre';
      state = state.copyWith(saving: false, error: message);
    }
  }

  Future<void> deleteClose(String id) async {
    state = state.copyWith(deletingId: id, clearError: true);
    try {
      await ref.read(contabilidadRepositoryProvider).deleteClose(id);
      state = state.copyWith(clearDeleting: true);
      await load();
    } catch (e) {
      final message =
          e is ApiException ? e.message : 'No se pudo eliminar el cierre';
      state = state.copyWith(error: message, clearDeleting: true);
    }
  }
}

CierresDateRange _currentQuincena(DateTime now) {
  DateTime safeDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day > lastDay ? lastDay : day;
    return DateTime(year, month, safeDay);
  }

  if (now.day >= 15 && now.day <= 29) {
    return CierresDateRange(
      from: safeDate(now.year, now.month, 15),
      to: DateTime(now.year, now.month, 29),
    );
  }

  if (now.day >= 30) {
    return CierresDateRange(
      from: safeDate(now.year, now.month, 30),
      to: DateTime(now.year, now.month + 1, 14),
    );
  }

  return CierresDateRange(
    from: safeDate(now.year, now.month - 1, 30),
    to: DateTime(now.year, now.month, 14),
  );
}
