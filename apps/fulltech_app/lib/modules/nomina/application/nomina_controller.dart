import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/nomina_repository.dart';
import '../nomina_models.dart';

class NominaHomeState {
  final bool loading;
  final String? error;
  final List<PayrollPeriod> periods;
  final List<PayrollEmployee> employees;
  final double? openPeriodTotal;

  const NominaHomeState({
    this.loading = false,
    this.error,
    this.periods = const [],
    this.employees = const [],
    this.openPeriodTotal,
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
    List<PayrollEmployee>? employees,
    double? openPeriodTotal,
    bool clearError = false,
    bool clearOpenPeriodTotal = false,
  }) {
    return NominaHomeState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      periods: periods ?? this.periods,
      employees: employees ?? this.employees,
      openPeriodTotal: clearOpenPeriodTotal
          ? null
          : (openPeriodTotal ?? this.openPeriodTotal),
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
    state = state.copyWith(
      loading: true,
      clearError: true,
      clearOpenPeriodTotal: true,
    );
    try {
      final periods = await _repo.listPeriods();
      final employees = await _repo.listEmployees(activeOnly: false);

      double? openTotal;
      PayrollPeriod? openPeriod;
      for (final period in periods) {
        if (period.isOpen) {
          openPeriod = period;
          break;
        }
      }

      if (openPeriod != null) {
        openTotal = await _repo.computePeriodTotalAllEmployees(openPeriod.id);
      }

      state = state.copyWith(
        loading: false,
        periods: periods,
        employees: employees,
        openPeriodTotal: openTotal,
      );
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
      throw Exception(
        'Ya existe una quincena abierta que se solapa con esas fechas.',
      );
    }

    final period = await _repo.createPeriod(start, end, title);
    await load();
    return period;
  }

  Future<void> closePeriod(String periodId) async {
    await _repo.closePeriod(periodId);
    await load();
  }

  Future<void> saveEmployee({
    String? id,
    required String nombre,
    String? telefono,
    String? puesto,
    double cuotaMinima = 0,
    bool activo = true,
  }) async {
    final trimmedName = nombre.trim();
    if (trimmedName.isEmpty) {
      throw Exception('El nombre del empleado es obligatorio');
    }

    if (cuotaMinima < 0) {
      throw Exception('La cuota mínima no puede ser negativa');
    }

    final existing = id == null ? null : await _repo.getEmployeeById(id);

    final employee = PayrollEmployee(
      id: existing?.id ?? '',
      ownerId: _repo.ownerId,
      nombre: trimmedName,
      telefono: (telefono ?? '').trim().isEmpty ? null : telefono!.trim(),
      puesto: (puesto ?? '').trim().isEmpty ? null : puesto!.trim(),
      cuotaMinima: cuotaMinima,
      activo: activo,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
    );

    await _repo.upsertEmployee(employee);
    await load();
  }
}
