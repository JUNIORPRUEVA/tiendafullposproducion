import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../features/user/data/users_repository.dart';
import 'application/nomina_controller.dart';
import 'data/nomina_repository.dart';
import 'nomina_models.dart';

class NominaScreen extends ConsumerWidget {
  const NominaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nominaTheme = theme.copyWith(
      scaffoldBackgroundColor: scheme.primary,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: theme.cardTheme.copyWith(
        color: scheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: theme.dialogTheme.copyWith(backgroundColor: scheme.surface),
    );

    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final isAdmin = currentUser?.role == 'ADMIN';

    if (!isAdmin) {
      return Theme(
        data: nominaTheme,
        child: Scaffold(
          appBar: AppBar(title: const Text('Nómina')),
          drawer: AppDrawer(currentUser: currentUser),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 46,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Este módulo es solo para administración',
                    style: TextStyle(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.misPagos),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Ir a Mis Pagos'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final state = ref.watch(nominaHomeControllerProvider);
    final controller = ref.read(nominaHomeControllerProvider.notifier);

    return Theme(
      data: nominaTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nómina'),
          actions: [
            IconButton(
              tooltip: 'Recargar',
              onPressed: state.loading ? null : controller.load,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Nueva quincena',
              onPressed: () => _showCreatePeriodDialog(context, ref),
              icon: const Icon(Icons.add),
            ),
            IconButton(
              tooltip: 'Exportar PDF',
              onPressed: () => _exportOpenPeriodPdf(context, ref, state),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        drawer: AppDrawer(currentUser: currentUser),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'nomina_historial_fab',
              onPressed: state.loading
                  ? null
                  : () => _openPayrollHistoryDialog(context, ref, state),
              icon: const Icon(Icons.history),
              label: const Text('Historial'),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'nomina_totales_fab',
              onPressed: state.loading
                  ? null
                  : () => _openOpenPeriodTotalsDialog(context, ref, state),
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Totales'),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: controller.load,
          child: state.loading && state.periods.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _NominaSummaryCard(state: state),
                        const SizedBox(height: 12),
                        if (state.error != null)
                          Card(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                state.error!,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ),
                        if (state.periods.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.event_note_outlined,
                                    size: 40,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Aún no hay quincenas creadas',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Crea la primera quincena para comenzar la gestión de nómina.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        _showCreatePeriodDialog(context, ref),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Crear quincena'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          Text(
                            'Quincenas',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          ...state.periods.map(
                            (period) => _PeriodCard(
                              period: period,
                              onClose: period.isOpen
                                  ? () => _confirmClosePeriod(
                                      context,
                                      ref,
                                      period,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Equipo de ventas (nómina)',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showEmployeeDialog(context, ref),
                              icon: const Icon(Icons.add),
                              label: const Text('Agregar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (state.employees.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: Text(
                                'No hay empleados de nómina registrados.',
                              ),
                            ),
                          )
                        else
                          ...state.employees.map(
                            (employee) => _EmployeeCard(
                              employee: employee,
                              onManage: () => _showEmployeePayrollDialog(
                                context,
                                ref,
                                employee,
                              ),
                              onEdit: () => _showEmployeeDialog(
                                context,
                                ref,
                                employee: employee,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Future<List<({PayrollEmployee employee, PayrollTotals totals})>>
  _loadOpenPeriodRows(WidgetRef ref, NominaHomeState state) async {
    final open = state.openPeriod;
    if (open == null) return const [];

    final repo = ref.read(nominaRepositoryProvider);
    final employees = [...state.employees]
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    final rows = <({PayrollEmployee employee, PayrollTotals totals})>[];
    for (final employee in employees) {
      final totals = await repo.computeTotals(open.id, employee.id);
      rows.add((employee: employee, totals: totals));
    }
    return rows;
  }

  Future<List<({PayrollEmployee employee, PayrollTotals totals})>>
  _loadRowsForPeriod(
    WidgetRef ref,
    NominaHomeState state,
    PayrollPeriod period,
  ) async {
    final repo = ref.read(nominaRepositoryProvider);
    final employees = [...state.employees]
      ..sort((a, b) => a.nombre.compareTo(b.nombre));

    final rows = <({PayrollEmployee employee, PayrollTotals totals})>[];
    for (final employee in employees) {
      final totals = await repo.computeTotals(period.id, employee.id);
      rows.add((employee: employee, totals: totals));
    }
    return rows;
  }

  Future<void> _openPayrollHistoryDialog(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final pastPeriods = state.periods.where((p) => !p.isOpen).toList();
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    if (pastPeriods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay quincenas pasadas para mostrar')),
      );
      return;
    }

    final repo = ref.read(nominaRepositoryProvider);
    final totalsByPeriod = <String, double>{};
    for (final period in pastPeriods) {
      totalsByPeriod[period.id] = await repo.computePeriodTotalAllEmployees(
        period.id,
      );
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Historial de nóminas'),
        content: SizedBox(
          width: 620,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: pastPeriods.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final period = pastPeriods[index];
              final total = totalsByPeriod[period.id] ?? 0;
              return ListTile(
                title: Text(
                  period.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('Total pagado: ${money.format(total)}'),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    await _openPastPeriodDetailsDialog(
                      context,
                      ref,
                      state,
                      period,
                    );
                  },
                  child: const Text('Ver detalles'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPastPeriodDetailsDialog(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
    PayrollPeriod period,
  ) async {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final rows = await _loadRowsForPeriod(ref, state, period);
    if (!context.mounted) return;

    final totalPagar = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalle ${period.title}'),
        content: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Empleados: ${rows.length}'),
              Text(
                'Total pagado quincena: ${money.format(totalPagar)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 340,
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      title: Text(
                        row.employee.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Base ${money.format(row.totals.baseSalary)} · Comisión ${money.format(row.totals.commissions)} · Deducciones ${money.format(row.totals.deductions)}',
                      ),
                      trailing: Text(
                        money.format(row.totals.total),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await _openOpenPeriodPdfPreviewDialog(context, period, rows);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOpenPeriodTotalsDialog(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final open = state.openPeriod;
    if (open == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay quincena abierta')));
      return;
    }

    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final rows = await _loadOpenPeriodRows(ref, state);
    if (!context.mounted) return;

    final totalBase = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.baseSalary,
    );
    final totalCommissions = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.commissions,
    );
    final totalBonos = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.bonuses + row.totals.otherAdditions,
    );
    final totalDeductions = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.deductions,
    );
    final totalPagar = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Totales de quincena actual'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quincena: ${open.title}'),
              Text('Empleados: ${rows.length}'),
              const SizedBox(height: 10),
              _summaryLine('Total base', money.format(totalBase)),
              _summaryLine(
                'Comisión por ventas',
                money.format(totalCommissions),
              ),
              _summaryLine('Bonos / extras', money.format(totalBonos)),
              _summaryLine('Deducciones', money.format(totalDeductions)),
              const Divider(height: 14),
              _summaryLine(
                'TOTAL GENERAL A PAGAR',
                money.format(totalPagar),
                highlight: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await _openOpenPeriodPdfPreviewDialog(context, open, rows);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Generar PDF'),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildOpenPeriodPayrollPdfBytes(
    PayrollPeriod open,
    List<({PayrollEmployee employee, PayrollTotals totals})> rows,
  ) async {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final doc = pw.Document();

    final totalBase = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.baseSalary,
    );
    final totalCommissions = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.commissions,
    );
    final totalBonos = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.bonuses + row.totals.otherAdditions,
    );
    final totalDeductions = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.deductions,
    );
    final totalPagar = rows.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            'Nómina quincenal - ${open.title}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
          ),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: const [
              'Empleado',
              'Base',
              'Comisión',
              'Bonos/Extras',
              'Deducciones',
              'Neto',
            ],
            data: rows
                .map(
                  (row) => [
                    row.employee.nombre,
                    money.format(row.totals.baseSalary),
                    money.format(row.totals.commissions),
                    money.format(
                      row.totals.bonuses + row.totals.otherAdditions,
                    ),
                    money.format(row.totals.deductions),
                    money.format(row.totals.total),
                  ],
                )
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 280,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _pdfTotalLine('Total base', money.format(totalBase)),
                  _pdfTotalLine('Comisión', money.format(totalCommissions)),
                  _pdfTotalLine('Bonos / extras', money.format(totalBonos)),
                  _pdfTotalLine('Deducciones', money.format(totalDeductions)),
                  pw.Divider(height: 10),
                  _pdfTotalLine(
                    'TOTAL GENERAL',
                    money.format(totalPagar),
                    highlight: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfTotalLine(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: highlight
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOpenPeriodPdfPreviewDialog(
    BuildContext context,
    PayrollPeriod open,
    List<({PayrollEmployee employee, PayrollTotals totals})> rows,
  ) async {
    final pdfBytes = await _buildOpenPeriodPayrollPdfBytes(open, rows);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 920,
          height: 760,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PDF Nómina · ${open.title}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final fileName =
                            'nomina_${open.title.replaceAll(' ', '_')}.pdf';
                        await Printing.sharePdf(
                          bytes: pdfBytes,
                          filename: fileName,
                        );
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Descargar'),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: PdfPreview(
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  allowPrinting: true,
                  allowSharing: true,
                  build: (_) async => pdfBytes,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEmployeeDialog(
    BuildContext context,
    WidgetRef ref, {
    PayrollEmployee? employee,
  }) async {
    UserModel? selectedUser;
    if (employee == null) {
      final existingUserIds = ref
          .read(nominaHomeControllerProvider)
          .employees
          .map((item) => item.id)
          .toSet();
      selectedUser = await _showUserPickerDialog(
        context,
        ref,
        excludedUserIds: existingUserIds,
      );
      if (selectedUser == null) return;
    }

    final nameCtrl = TextEditingController(
      text: employee?.nombre ?? selectedUser?.nombreCompleto ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: employee?.telefono ?? selectedUser?.telefono ?? '',
    );
    final roleCtrl = TextEditingController(
      text: employee?.puesto ?? selectedUser?.role ?? '',
    );
    final salaryCtrl = TextEditingController(text: employee == null ? '0' : '');
    final seguroLeyCtrl = TextEditingController(
      text: (employee?.seguroLeyMonto ?? 0).toStringAsFixed(2),
    );
    final cuotaCtrl = TextEditingController(
      text: (employee?.cuotaMinima ?? 0).toStringAsFixed(2),
    );

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(employee == null ? 'Agregar empleado' : 'Editar empleado'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(labelText: 'Puesto'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: salaryCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Salario base quincenal',
                  helperText: 'Se aplica a la quincena abierta',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cuotaCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Cuota mínima (meta quincenal)',
                  helperText: 'Meta de ventas quincenal del empleado',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: seguroLeyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Seguro de ley (monto)',
                  helperText: 'Deducción fija por quincena',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final salaryText = salaryCtrl.text.trim();
              final salary = salaryText.isEmpty
                  ? null
                  : double.tryParse(salaryText);
              if (employee == null && salary == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El salario base es obligatorio al agregar'),
                  ),
                );
                return;
              }
              if (salary != null && salary < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El salario base debe ser un número >= 0'),
                  ),
                );
                return;
              }
              final cuota = double.tryParse(cuotaCtrl.text.trim()) ?? -1;
              if (cuota < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La cuota mínima debe ser un número >= 0'),
                  ),
                );
                return;
              }
              final seguroLey =
                  double.tryParse(seguroLeyCtrl.text.trim()) ?? -1;
              if (seguroLey < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El seguro de ley debe ser un monto >= 0'),
                  ),
                );
                return;
              }

              if (employee == null && selectedUser != null) {
                final alreadyExists = ref
                    .read(nominaHomeControllerProvider)
                    .employees
                    .any((item) => item.id == selectedUser!.id);
                if (alreadyExists) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Este usuario ya está agregado en nómina'),
                    ),
                  );
                  return;
                }
              }

              try {
                await ref
                    .read(nominaHomeControllerProvider.notifier)
                    .saveEmployee(
                      id: employee?.id ?? selectedUser?.id,
                      nombre: nameCtrl.text,
                      telefono: phoneCtrl.text,
                      puesto: roleCtrl.text,
                      salarioBase: salary,
                      cuotaMinima: cuota,
                      seguroLeyMonto: seguroLey,
                      activo: employee?.activo ?? true,
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      employee == null
                          ? 'Empleado agregado'
                          : 'Empleado actualizado',
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo guardar: $e')),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEmployeePayrollDialog(
    BuildContext context,
    WidgetRef ref,
    PayrollEmployee employee,
  ) async {
    final state = ref.read(nominaHomeControllerProvider);
    final open = state.openPeriod;
    if (open == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay quincena abierta')));
      return;
    }

    final repo = ref.read(nominaRepositoryProvider);
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    var entries = await repo.listEntries(open.id, employee.id);
    var totals = await repo.computeTotals(open.id, employee.id);
    final config = await repo.getEmployeeConfig(open.id, employee.id);

    final conceptCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    PayrollEntryType selectedType = PayrollEntryType.descuento;

    Future<void> reload(StateSetter setStateDialog) async {
      entries = await repo.listEntries(open.id, employee.id);
      totals = await repo.computeTotals(open.id, employee.id);
      setStateDialog(() {});
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Nómina de ${employee.nombre}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quincena: ${open.title}'),
                  const SizedBox(height: 6),
                  Text(
                    'Salario base: ${money.format(config?.baseSalary ?? 0)}',
                  ),
                  Text(
                    'Comisión por ventas (auto): ${money.format(totals.salesCommissionAuto)}',
                    style: TextStyle(
                      color: totals.salesGoalReached
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Meta (puntos): ${money.format(totals.salesGoal)} · Puntos: ${money.format(totals.salesAmountThisPeriod)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    totals.salesGoalReached
                        ? 'Meta alcanzada en puntos: comisión por ventas habilitada automáticamente.'
                        : 'Meta no alcanzada en puntos: comisión por ventas en RD\$0.00.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text('Seguro ley: ${money.format(totals.seguroLey)}'),
                  Text(
                    'Total neto: ${money.format(totals.total)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Agregar ajuste',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PayrollEntryType>(
                    value: selectedType,
                    items: PayrollEntryType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setStateDialog(() => selectedType = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: conceptCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Concepto',
                      hintText:
                          'Ej: Ausencia 12/02, bonificación por meta, combustible...',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Monto (opcional en ausencia)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final concept = conceptCtrl.text.trim();
                      if (concept.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Debes escribir un concepto'),
                          ),
                        );
                        return;
                      }
                      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1;
                      if (qty <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('La cantidad debe ser > 0'),
                          ),
                        );
                        return;
                      }

                      final parsedAmount = double.tryParse(
                        amountCtrl.text.trim(),
                      );
                      double amount;

                      if (selectedType == PayrollEntryType.ausencia &&
                          parsedAmount == null) {
                        final daily = (config?.baseSalary ?? 0) / 15;
                        amount = -(daily * qty);
                      } else {
                        if (parsedAmount == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Monto inválido')),
                          );
                          return;
                        }
                        amount = parsedAmount;
                      }

                      if (selectedType.isDeduction && amount > 0) {
                        amount = -amount;
                      }
                      if (!selectedType.isDeduction &&
                          selectedType != PayrollEntryType.otro &&
                          amount < 0) {
                        amount = amount.abs();
                      }

                      await repo.addEntry(
                        PayrollEntry(
                          id: '',
                          ownerId: repo.ownerId,
                          periodId: open.id,
                          employeeId: employee.id,
                          date: DateTime.now(),
                          type: selectedType,
                          concept: concept,
                          amount: amount,
                          cantidad: qty,
                        ),
                      );

                      conceptCtrl.clear();
                      amountCtrl.clear();
                      qtyCtrl.text = '1';
                      await reload(setStateDialog);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ajuste guardado')),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar ajuste'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Movimientos de la quincena',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (entries.isEmpty)
                    const Text('Sin movimientos registrados')
                  else
                    ...entries.map(
                      (entry) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${entry.type.label}: ${entry.concept}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy').format(entry.date),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              money.format(entry.amount),
                              style: TextStyle(
                                color: entry.amount < 0
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              onPressed: () async {
                                await repo.deleteEntry(entry.id);
                                await reload(setStateDialog);
                              },
                              icon: const Icon(Icons.delete_outline, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;
    await ref.read(nominaHomeControllerProvider.notifier).load();
  }

  Future<void> _exportOpenPeriodPdf(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final open = state.openPeriod;
    if (open == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay quincena abierta para exportar')),
      );
      return;
    }

    final rows = await _loadOpenPeriodRows(ref, state);
    final bytes = await _buildOpenPeriodPayrollPdfBytes(open, rows);
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  Future<UserModel?> _showUserPickerDialog(
    BuildContext context,
    WidgetRef ref, {
    Set<String> excludedUserIds = const {},
  }) async {
    final searchCtrl = TextEditingController();
    List<UserModel> users = const [];

    try {
      users = await ref.read(usersRepositoryProvider).fetchUsers();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar usuarios: $e')),
        );
      }
      return null;
    }

    UserModel? selected;

    return showDialog<UserModel>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final visible = users.where((u) {
            if (excludedUserIds.contains(u.id)) return false;
            if (query.isEmpty) return true;
            return u.nombreCompleto.toLowerCase().contains(query) ||
                u.email.toLowerCase().contains(query) ||
                u.telefono.toLowerCase().contains(query);
          }).toList();

          return AlertDialog(
            title: const Text('Seleccionar usuario'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Buscar usuario...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 300,
                    child: visible.isEmpty
                        ? const Center(
                            child: Text('No hay usuarios para mostrar'),
                          )
                        : ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final user = visible[index];
                              return RadioListTile<String>(
                                value: user.id,
                                groupValue: selected?.id,
                                dense: true,
                                title: Text(
                                  user.nombreCompleto,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  user.telefono.isEmpty
                                      ? user.email
                                      : '${user.telefono} · ${user.email}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onChanged: (_) =>
                                    setDialogState(() => selected = user),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(context, selected),
                child: const Text('Seleccionar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCreatePeriodDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleCtrl = TextEditingController();
    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(days: 14));

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Nueva quincena'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Inicio'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(start)),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: start,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setStateDialog(() => start = picked);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fin'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(end)),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: end,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setStateDialog(() => end = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Debes indicar un título')),
                  );
                  return;
                }
                try {
                  await ref
                      .read(nominaHomeControllerProvider.notifier)
                      .createPeriod(start: start, end: end, title: title);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Quincena creada correctamente'),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo crear: $e')),
                  );
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClosePeriod(
    BuildContext context,
    WidgetRef ref,
    PayrollPeriod period,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar quincena'),
        content: Text('¿Deseas cerrar "${period.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      await ref
          .read(nominaHomeControllerProvider.notifier)
          .closePeriod(period.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Quincena cerrada')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cerrar: $e')));
    }
  }
}

class _NominaSummaryCard extends StatelessWidget {
  const _NominaSummaryCard({required this.state});

  final NominaHomeState state;

  @override
  Widget build(BuildContext context) {
    final open = state.openPeriod;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.payments_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen de nómina',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('Quincenas: ${state.periods.length}'),
                  Text(
                    open != null
                        ? 'Abierta: ${open.title}'
                        : 'No hay quincena abierta',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.onClose});

  final PayrollPeriod period;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final dateRange =
        '${DateFormat('dd/MM/yyyy').format(period.startDate)} - ${DateFormat('dd/MM/yyyy').format(period.endDate)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Text(
          period.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(dateRange),
        trailing: period.isOpen
            ? FilledButton.tonal(
                onPressed: onClose,
                child: const Text('Cerrar'),
              )
            : const Chip(label: Text('Cerrada')),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.onEdit,
    required this.onManage,
  });

  final PayrollEmployee employee;
  final VoidCallback onEdit;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          employee.nombre,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Puesto: ${employee.puesto ?? 'N/A'}\n'
          'Cuota mínima: ${money.format(employee.cuotaMinima)} · Seguro ley: ${money.format(employee.seguroLeyMonto)}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Movimientos de nómina',
              onPressed: onManage,
              icon: const Icon(Icons.calculate_outlined),
            ),
            IconButton(
              tooltip: 'Editar',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}
