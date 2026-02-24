import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../data/ventas_repository.dart';
import '../sales_models.dart';

enum SalesRangePreset { today, week, quincena, custom }

class VentasState {
  final bool loading;
  final String? error;
  final List<SaleModel> sales;
  final SalesSummaryModel summary;
  final SalesRangePreset preset;
  final DateTime from;
  final DateTime to;

  const VentasState({
    this.loading = false,
    this.error,
    this.sales = const [],
    required this.summary,
    required this.preset,
    required this.from,
    required this.to,
  });

  factory VentasState.initial() {
    final now = DateTime.now();
    final range = _currentQuincena(now);
    return VentasState(
      loading: false,
      summary: SalesSummaryModel.empty(),
      preset: SalesRangePreset.quincena,
      from: range.from,
      to: range.to,
    );
  }

  VentasState copyWith({
    bool? loading,
    String? error,
    List<SaleModel>? sales,
    SalesSummaryModel? summary,
    SalesRangePreset? preset,
    DateTime? from,
    DateTime? to,
    bool clearError = false,
  }) {
    return VentasState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      sales: sales ?? this.sales,
      summary: summary ?? this.summary,
      preset: preset ?? this.preset,
      from: from ?? this.from,
      to: to ?? this.to,
    );
  }
}

final ventasControllerProvider =
    StateNotifierProvider<VentasController, VentasState>((ref) {
      return VentasController(ref);
    });

class VentasController extends StateNotifier<VentasState> {
  final Ref ref;

  VentasController(this.ref) : super(VentasState.initial()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = ref.read(ventasRepositoryProvider);
      final results = await Future.wait([
        repo.listSales(from: state.from, to: state.to),
        repo.summary(from: state.from, to: state.to),
      ]);

      state = state.copyWith(
        loading: false,
        sales: results[0] as List<SaleModel>,
        summary: results[1] as SalesSummaryModel,
      );
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar las ventas';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> refresh() => load();

  Future<void> deleteSale(String id) async {
    final previous = state.sales;
    state = state.copyWith(
      sales: state.sales.where((sale) => sale.id != id).toList(),
    );

    try {
      await ref.read(ventasRepositoryProvider).deleteSale(id);
      await load();
    } catch (_) {
      state = state.copyWith(sales: previous);
      rethrow;
    }
  }

  Future<void> setPreset(SalesRangePreset preset) async {
    final now = DateTime.now();
    SalesDateRange nextRange;

    switch (preset) {
      case SalesRangePreset.today:
        final day = DateTime(now.year, now.month, now.day);
        nextRange = SalesDateRange(from: day, to: day);
        break;
      case SalesRangePreset.week:
        final weekday = now.weekday;
        final from = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: weekday - 1));
        final to = from.add(const Duration(days: 6));
        nextRange = SalesDateRange(from: from, to: to);
        break;
      case SalesRangePreset.quincena:
        nextRange = _currentQuincena(now);
        break;
      case SalesRangePreset.custom:
        nextRange = SalesDateRange(from: state.from, to: state.to);
        break;
    }

    state = state.copyWith(
      preset: preset,
      from: nextRange.from,
      to: nextRange.to,
    );

    await load();
  }

  Future<void> setCustomRange(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return;

    state = state.copyWith(
      preset: SalesRangePreset.custom,
      from: start,
      to: end,
    );
    await load();
  }
}

SalesDateRange _currentQuincena(DateTime now) {
  final day = now.day;
  if (day <= 15) {
    final prevMonthLastDay = DateTime(now.year, now.month, 0);
    return SalesDateRange(
      from: DateTime(
        prevMonthLastDay.year,
        prevMonthLastDay.month,
        prevMonthLastDay.day,
      ),
      to: DateTime(now.year, now.month, 15),
    );
  }

  return SalesDateRange(
    from: DateTime(now.year, now.month, 16),
    to: DateTime(now.year, now.month + 1, 0),
  );
}
