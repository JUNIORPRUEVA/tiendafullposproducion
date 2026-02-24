import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import 'nomina_database_helper.dart';
import '../nomina_models.dart';

final nominaRepositoryProvider = Provider<NominaRepository>((ref) {
  return NominaRepository(ref, NominaDatabaseHelper.instance);
});

class NominaRepository {
  NominaRepository(this.ref, this.db);

  final Ref ref;
  final NominaDatabaseHelper db;

  String get _ownerId => NominaDatabaseHelper.ownerIdOrDefault(
    ref.read(authStateProvider).user?.id,
  );

  Future<List<PayrollPeriod>> listPeriods() => db.listPeriods(_ownerId);

  Future<PayrollPeriod?> getPeriodById(String periodId) =>
      db.getPeriodById(_ownerId, periodId);

  Future<bool> hasOverlappingOpenPeriod(DateTime start, DateTime end) =>
      db.hasOverlappingOpenPeriod(_ownerId, start, end);

  Future<PayrollPeriod> createPeriod(
    DateTime start,
    DateTime end,
    String title,
  ) => db.createPeriod(_ownerId, start, end, title);

  Future<void> closePeriod(String periodId) =>
      db.closePeriod(_ownerId, periodId);

  Future<List<PayrollEmployee>> listEmployees({bool activeOnly = true}) =>
      db.listEmployees(_ownerId, activeOnly: activeOnly);

  Future<PayrollEmployee?> getEmployeeById(String employeeId) =>
      db.getEmployeeById(_ownerId, employeeId);

  Future<PayrollEmployee> upsertEmployee(PayrollEmployee employee) =>
      db.upsertEmployee(_ownerId, employee);

  Future<PayrollEmployeeConfig?> getEmployeeConfig(
    String periodId,
    String employeeId,
  ) => db.getEmployeeConfig(_ownerId, periodId, employeeId);

  Future<PayrollEmployeeConfig> upsertEmployeeConfig({
    required String periodId,
    required String employeeId,
    required double baseSalary,
    required bool includeCommissions,
    String? notes,
  }) => db.upsertEmployeeConfig(
    ownerId: _ownerId,
    periodId: periodId,
    employeeId: employeeId,
    baseSalary: baseSalary,
    includeCommissions: includeCommissions,
    notes: notes,
  );

  Future<List<PayrollEntry>> listEntries(String periodId, String employeeId) =>
      db.listEntries(_ownerId, periodId, employeeId);

  Future<PayrollEntry> addEntry(PayrollEntry entry) =>
      db.addEntry(_ownerId, entry);

  Future<void> deleteEntry(String entryId) => db.deleteEntry(_ownerId, entryId);

  Future<PayrollTotals> computeTotals(String periodId, String employeeId) =>
      db.computeTotals(_ownerId, periodId, employeeId);

  Future<double> computePeriodTotalAllEmployees(String periodId) =>
      db.computePeriodTotalAllEmployees(_ownerId, periodId);

  Future<List<PayrollHistoryItem>> listMyPayrollHistory() =>
      db.listPayrollHistoryByEmployee(_ownerId, _ownerId);

  String get ownerId => _ownerId;
}
