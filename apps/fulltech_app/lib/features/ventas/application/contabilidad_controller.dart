import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/close_model.dart';
import '../data/contabilidad_repository.dart';
import '../data/sales_repository.dart';

class ContabilidadState {
  final List<CloseModel> closes;
  final bool loading;
  final String? error;
  final DateTime? from;
  final DateTime? to;

  const ContabilidadState({
    this.closes = const [],
    this.loading = false,
    this.error,
    this.from,
    this.to,
  });

  ContabilidadState copyWith({
    List<CloseModel>? closes,
    bool? loading,
    String? error,
    bool clearError = false,
    DateTime? from,
    DateTime? to,
  }) {
    return ContabilidadState(
      closes: closes ?? this.closes,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }

  Map<String, dynamic> get summary {
    double totalCash = 0;
    double totalTransfer = 0;
    double totalCard = 0;
    double totalExpenses = 0;
    double totalDelivered = 0;
    int count = closes.length;

    for (final close in closes) {
      totalCash += close.cash;
      totalTransfer += close.transfer;
      totalCard += close.card;
      totalExpenses += close.expenses;
      totalDelivered += close.cashDelivered;
    }

    return {
      'count': count,
      'totalCash': totalCash.toStringAsFixed(2),
      'totalTransfer': totalTransfer.toStringAsFixed(2),
      'totalCard': totalCard.toStringAsFixed(2),
      'totalIncome': (totalCash + totalTransfer + totalCard).toStringAsFixed(2),
      'totalExpenses': totalExpenses.toStringAsFixed(2),
      'totalDelivered': totalDelivered.toStringAsFixed(2),
      'cashOnHand': (totalCash - totalExpenses - totalDelivered).toStringAsFixed(2),
    };
  }
}

final contabilidadProvider = StateNotifierProvider<ContabilidadController, ContabilidadState>((ref) {
  return ContabilidadController(ref);
});

class ContabilidadController extends StateNotifier<ContabilidadState> {
  final Ref ref;
  ContabilidadController(this.ref) : super(const ContabilidadState()) {
    load();
  }

  Future<void> load({DateTime? from, DateTime? to}) async {
    state = state.copyWith(loading: true, clearError: true, from: from, to: to);
    try {
      final repo = ref.read(salesRepositoryProvider);
      final closes = await repo.getCloses(from: from, to: to);
      state = state.copyWith(closes: closes, loading: false);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudieron cargar los cierres';
      state = state.copyWith(loading: false, error: msg);
    }
  }

  Future<void> createClose({
    required CloseType type,
    required String status,
    required double cash,
    required double transfer,
    required double card,
    required double expenses,
    required double cashDelivered,
    DateTime? date,
  }) async {
    try {
      final repo = ref.read(salesRepositoryProvider);
      final created = await repo.createClose(
        type: type,
        status: status,
        cash: cash,
        transfer: transfer,
        card: card,
        expenses: expenses,
        cashDelivered: cashDelivered,
        date: date,
      );
      state = state.copyWith(closes: [created, ...state.closes]);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo crear el cierre';
      state = state.copyWith(error: msg);
      rethrow;
    }
  }

  Future<void> updateClose(String id, {
    String? status,
    double? cash,
    double? transfer,
    double? card,
    double? expenses,
    double? cashDelivered,
  }) async {
    try {
      final repo = ref.read(salesRepositoryProvider);
      final updated = await repo.updateClose(id,
        status: status,
        cash: cash,
        transfer: transfer,
        card: card,
        expenses: expenses,
        cashDelivered: cashDelivered,
      );
      final newCloses = state.closes.map((c) => c.id == id ? updated : c).toList();
      state = state.copyWith(closes: newCloses);
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo actualizar el cierre';
      state = state.copyWith(error: msg);
      rethrow;
    }
  }

  Future<void> deleteClose(String id) async {
    try {
      final repo = ref.read(salesRepositoryProvider);
      await repo.deleteClose(id);
      state = state.copyWith(closes: state.closes.where((c) => c.id != id).toList());
    } catch (e) {
      final msg = e is ApiException ? e.message : 'No se pudo eliminar el cierre';
      state = state.copyWith(error: msg);
      rethrow;
    }
  }
}