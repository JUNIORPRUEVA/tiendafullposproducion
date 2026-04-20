import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/debug/trace_log.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../features/user/data/users_repository.dart';
import 'application/nomina_controller.dart';
import 'data/nomina_repository.dart';
import 'nomina_models.dart';

typedef _PayrollPeriodRow = ({PayrollEmployee employee, PayrollTotals totals});

class NominaScreen extends ConsumerStatefulWidget {
  const NominaScreen({super.key});

  @override
  ConsumerState<NominaScreen> createState() => _NominaScreenState();
}

class _NominaScreenState extends ConsumerState<NominaScreen> {
  bool _showEmployeesSection = false;

  Widget _buildDesktopAdminBody(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final openPeriod = state.openPeriod;
    final activePayrollEmployees = state.employees
        .where((employee) => employee.activo)
        .toList(growable: false);
    final activeEmployees = activePayrollEmployees.length;
    final payrollBase = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.salarioBaseQuincenal,
    );
    final payrollQuota = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.cuotaMinima,
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF6F8), Color(0xFFF5F8FB), Color(0xFFF5F8FB)],
          stops: [0, 0.22, 0.22],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: ref.read(nominaHomeControllerProvider.notifier).load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NominaPremiumHeroCard(
                    title: openPeriod?.title ?? 'Nomina sin quincena abierta',
                    range: openPeriod == null
                        ? 'Abre una quincena para comenzar'
                        : '${DateFormat('dd/MM/yyyy').format(openPeriod.startDate)} - ${DateFormat('dd/MM/yyyy').format(openPeriod.endDate)}',
                    totalLabel: money.format(state.openPeriodTotal ?? 0),
                    activeEmployees: activeEmployees,
                    onHistory: state.loading
                        ? null
                        : () => _openPayrollHistoryDialog(context, ref, state),
                    onTotals: state.loading
                        ? null
                        : () =>
                              _openOpenPeriodTotalsDialog(context, ref, state),
                    onPdf: state.loading
                        ? null
                        : () => _exportOpenPeriodPdf(context, ref, state),
                    onAddEmployee: () => _showEmployeeDialog(context, ref),
                    onClosePeriod: openPeriod == null
                        ? null
                        : () => _confirmClosePeriod(context, ref, openPeriod),
                    onCreatePeriod: openPeriod == null
                        ? () => _showCreatePeriodDialog(context, ref)
                        : null,
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 10),
                    _NominaErrorBanner(message: state.error!),
                  ],
                  const SizedBox(height: 10),
                  _NominaPrimaryBoard(
                    openPeriod: openPeriod,
                    totalAbierto: state.openPeriodTotal ?? 0,
                    payrollBase: payrollBase,
                    payrollQuota: payrollQuota,
                    activeEmployees: activeEmployees,
                    money: money,
                  ),
                  const SizedBox(height: 10),
                  _NominaUsersSectionCard(
                    expanded: _showEmployeesSection,
                    employees: activePayrollEmployees,
                    onToggle: () => setState(
                      () => _showEmployeesSection = !_showEmployeesSection,
                    ),
                    onAdd: () => _showEmployeeDialog(context, ref),
                    child: activePayrollEmployees.isEmpty
                        ? _NominaEmptyState(
                            icon: Icons.groups_outlined,
                            title: 'No hay usuarios en nomina',
                            message: 'Agrega el primer usuario para comenzar.',
                            actionLabel: 'Agregar usuario',
                            onAction: () => _showEmployeeDialog(context, ref),
                          )
                        : Column(
                            children: activePayrollEmployees
                                .map(
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
                                    onDelete: () => _confirmDeleteEmployee(
                                      context,
                                      ref,
                                      employee,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
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

  Widget _buildMobileAdminBody(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) {
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final openPeriod = state.openPeriod;
    final activePayrollEmployees = state.employees
        .where((employee) => employee.activo)
        .toList(growable: false);
    final activeEmployees = activePayrollEmployees.length;
    final payrollBase = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.salarioBaseQuincenal,
    );
    final payrollQuota = activePayrollEmployees.fold<double>(
      0,
      (sum, employee) => sum + employee.cuotaMinima,
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAF6F8), Color(0xFFF5F8FB), Color(0xFFF5F8FB)],
          stops: [0, 0.22, 0.22],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: ref.read(nominaHomeControllerProvider.notifier).load,
        child: state.loading && state.periods.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
                    children: [
                      _NominaPremiumHeroCard(
                        title:
                            openPeriod?.title ?? 'Nomina sin quincena abierta',
                        range: openPeriod == null
                            ? 'Abre una quincena para comenzar'
                            : '${DateFormat('dd/MM/yyyy').format(openPeriod.startDate)} - ${DateFormat('dd/MM/yyyy').format(openPeriod.endDate)}',
                        totalLabel: money.format(state.openPeriodTotal ?? 0),
                        activeEmployees: activeEmployees,
                        onHistory: state.loading
                            ? null
                            : () => _openPayrollHistoryDialog(
                                context,
                                ref,
                                state,
                              ),
                        onTotals: state.loading
                            ? null
                            : () => _openOpenPeriodTotalsDialog(
                                context,
                                ref,
                                state,
                              ),
                        onPdf: state.loading
                            ? null
                            : () => _exportOpenPeriodPdf(context, ref, state),
                        onAddEmployee: () => _showEmployeeDialog(context, ref),
                        onClosePeriod: openPeriod == null
                            ? null
                            : () =>
                                  _confirmClosePeriod(context, ref, openPeriod),
                        onCreatePeriod: openPeriod == null
                            ? () => _showCreatePeriodDialog(context, ref)
                            : null,
                        compact: true,
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 10),
                        _NominaErrorBanner(message: state.error!),
                      ],
                      const SizedBox(height: 10),
                      _NominaPrimaryBoard(
                        openPeriod: openPeriod,
                        totalAbierto: state.openPeriodTotal ?? 0,
                        payrollBase: payrollBase,
                        payrollQuota: payrollQuota,
                        activeEmployees: activeEmployees,
                        money: money,
                        compact: true,
                      ),
                      const SizedBox(height: 10),
                      _NominaUsersSectionCard(
                        expanded: _showEmployeesSection,
                        employees: activePayrollEmployees,
                        onToggle: () => setState(
                          () => _showEmployeesSection = !_showEmployeesSection,
                        ),
                        onAdd: () => _showEmployeeDialog(context, ref),
                        child: activePayrollEmployees.isEmpty
                            ? _NominaEmptyState(
                                icon: Icons.groups_outlined,
                                title: 'No hay usuarios en nomina',
                                message:
                                    'Agrega un usuario nuevo cuando lo necesites.',
                                actionLabel: 'Agregar usuario',
                                onAction: () =>
                                    _showEmployeeDialog(context, ref),
                              )
                            : Column(
                                children: activePayrollEmployees
                                    .map(
                                      (employee) => _EmployeeCard(
                                        employee: employee,
                                        onManage: () =>
                                            _showEmployeePayrollDialog(
                                              context,
                                              ref,
                                              employee,
                                            ),
                                        onEdit: () => _showEmployeeDialog(
                                          context,
                                          ref,
                                          employee: employee,
                                        ),
                                        onDelete: () => _confirmDeleteEmployee(
                                          context,
                                          ref,
                                          employee,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nominaTheme = theme.copyWith(
      scaffoldBackgroundColor: scheme.primary,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: theme.appBarTheme.backgroundColor,
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
    final isDesktop = MediaQuery.sizeOf(context).width >= 1240;

    if (!isAdmin) {
      return Theme(
        data: nominaTheme,
        child: Scaffold(
          appBar: const CustomAppBar(
            title: 'Nómina',
            showLogo: false,
            showDepartmentLabel: false,
          ),
          drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
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
        appBar: CustomAppBar(
          title: 'Nómina',
          showLogo: false,
          showDepartmentLabel: false,
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
          ],
        ),
        drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
        floatingActionButton: null,
        body: isDesktop
            ? _buildDesktopAdminBody(context, ref, state)
            : _buildMobileAdminBody(context, ref, state),
      ),
    );
  }

  Future<void> _confirmDeleteEmployee(
    BuildContext context,
    WidgetRef ref,
    PayrollEmployee employee,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar de nómina'),
        content: Text(
          '¿Deseas eliminar a "${employee.nombre}" de nómina?\n\n'
          'Esto no elimina el usuario de la app, solo lo quita del módulo de nómina.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref
          .read(nominaHomeControllerProvider.notifier)
          .deleteEmployee(employee.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empleado eliminado de nómina')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  Future<List<({PayrollEmployee employee, PayrollTotals totals})>>
  _loadOpenPeriodRows(WidgetRef ref, NominaHomeState state) async {
    final open = state.openPeriod;
    if (open == null) return const [];

    final repo = ref.read(nominaRepositoryProvider);
    final employees =
        state.employees
            .where((employee) => employee.activo)
            .toList(growable: false)
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

    if (pastPeriods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay quincenas pasadas para mostrar')),
      );
      return;
    }

    final repo = ref.read(nominaRepositoryProvider);
    final historyItems = <_PayrollHistoryPeriodSummary>[];
    for (final period in pastPeriods) {
      final total = await repo.computePeriodTotalAllEmployees(period.id);
      historyItems.add(
        _PayrollHistoryPeriodSummary(period: period, total: total),
      );
    }
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => _PayrollHistoryFullScreen(
          items: historyItems,
          onOpenDetails: (period) =>
              _openPastPeriodDetailsDialog(routeContext, ref, state, period),
        ),
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

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => _PayrollPeriodDetailsScreen(
          period: period,
          rows: rows,
          totalPagar: totalPagar,
          onOpenPdf: () =>
              _openOpenPeriodPdfPreviewDialog(routeContext, period, rows),
          onSendPayroll: (row) => _sendPayrollToWhatsApp(
            routeContext,
            ref,
            period: period,
            employee: row.employee,
            totals: row.totals,
          ),
          money: money,
        ),
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
          pw.TableHelper.fromTextArray(
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

  Future<Uint8List> _buildEmployeePayrollPdfBytes({
    required WidgetRef ref,
    required PayrollPeriod period,
    required PayrollEmployee employee,
    required PayrollTotals totals,
  }) async {
    final settings = await ref.read(companySettingsRepositoryProvider).getSettings();
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final companyName = settings.companyName.trim().isEmpty
        ? 'FULLTECH'
        : settings.companyName.trim();
    final companyRnc = settings.rnc.trim();
    final companyPhone = settings.phone.trim();
    final range =
        '${DateFormat('dd/MM/yyyy').format(period.startDate)} - ${DateFormat('dd/MM/yyyy').format(period.endDate)}';
    final extras = totals.bonuses + totals.otherAdditions;
    final roleLabel = (employee.puesto ?? '').trim().isEmpty
        ? 'Empleado'
        : employee.puesto!.trim();

    final doc = pw.Document(title: 'Nomina ${employee.nombre}', author: companyName);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (companyRnc.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('RNC: $companyRnc'),
                    ],
                    if (companyPhone.isNotEmpty) pw.Text('Tel: $companyPhone'),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'COMPROBANTE DE PAGO DE NÓMINA',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Divider(),
              pw.SizedBox(height: 6),
              pw.Text('Empleado: ${employee.nombre}'),
              pw.Text('Cargo: $roleLabel'),
              pw.Text('Quincena: ${period.title}'),
              pw.Text('Rango: $range'),
              pw.SizedBox(height: 16),
              pw.Text('Salario quincenal: ${money.format(totals.baseSalary)}'),
              pw.Text('Comisión: ${money.format(totals.commissions)}'),
              pw.Text('Extras: ${money.format(extras)}'),
              pw.Text(
                'Beneficios: ${money.format(totals.commissions + extras)}',
              ),
              pw.Text('Deducciones: ${money.format(totals.deductions)}'),
              if (totals.absences > 0)
                pw.Text('Ausencias: ${money.format(totals.absences)}'),
              if (totals.advances > 0)
                pw.Text('Adelantos: ${money.format(totals.advances)}'),
              if (totals.otherDeductions > 0)
                pw.Text(
                  'Otras deducciones: ${money.format(totals.otherDeductions)}',
                ),
              pw.Divider(),
              pw.Text(
                'Neto a pagar: ${money.format(totals.total)}',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  String _buildEmployeePayrollPdfFileName(
    PayrollEmployee employee,
    PayrollPeriod period,
  ) {
    String sanitize(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
    }

    final employeeSlug = sanitize(employee.nombre).isEmpty
        ? 'empleado'
        : sanitize(employee.nombre);
    final periodSlug = sanitize(period.title).isEmpty
        ? 'quincena'
        : sanitize(period.title);
    return 'nomina_${employeeSlug}_$periodSlug.pdf';
  }

  Future<void> _sendPayrollToWhatsApp(
    BuildContext context,
    WidgetRef ref, {
    required PayrollPeriod period,
    required PayrollEmployee employee,
    required PayrollTotals totals,
  }) async {
    final repo = ref.read(nominaRepositoryProvider);
    final bytes = await _buildEmployeePayrollPdfBytes(
      ref: ref,
      period: period,
      employee: employee,
      totals: totals,
    );

    await repo.sendPayrollToWhatsApp(
      employeeId: employee.id,
      periodId: period.id,
      bytes: bytes,
      fileName: _buildEmployeePayrollPdfFileName(employee, period),
    );

    if (!context.mounted) return;
    await AppFeedback.showInfo(
      context,
      'Nómina enviada por WhatsApp a ${employee.nombre}',
      fallbackContext: context,
      scope: 'NominaSendPayroll',
    );
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
    final scaffoldContext = context;
    final flowSeq = TraceLog.nextSeq();
    TraceLog.log(
      'NominaEmployeeDialog',
      'open employeeId=${employee?.id ?? 'new'} scaffoldMounted=${scaffoldContext.mounted}',
      seq: flowSeq,
    );

    UserModel? selectedUser;
    if (employee == null) {
      final existingUserIds = ref
          .read(nominaHomeControllerProvider)
          .employees
          .where((item) => item.activo)
          .map((item) => item.id)
          .toSet();
      selectedUser = await showDialog<UserModel>(
        context: context,
        builder: (_) =>
            _PayrollUserPickerDialog(excludedUserIds: existingUserIds),
      );
      if (!context.mounted) return;
      if (selectedUser == null) return;
    }

    final successMessage = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayrollEmployeeDialog(
        employee: employee,
        selectedUser: selectedUser,
        traceSeq: flowSeq,
      ),
    );

    if (successMessage == null || !scaffoldContext.mounted) return;

    await AppFeedback.showInfo(
      scaffoldContext,
      successMessage,
      fallbackContext: scaffoldContext,
      scope: 'NominaEmployeeDialog',
    );
  }

  Future<void> _showEmployeePayrollDialog(
    BuildContext context,
    WidgetRef ref,
    PayrollEmployee employee,
  ) async {
    final scaffoldContext = context;
    final flowSeq = TraceLog.nextSeq();
    TraceLog.log(
      'NominaEmployeePayrollDialog',
      'open employeeId=${employee.id} scaffoldMounted=${scaffoldContext.mounted}',
      seq: flowSeq,
    );

    final state = ref.read(nominaHomeControllerProvider);
    final open = state.openPeriod;
    if (open == null) {
      await AppFeedback.showError(
        scaffoldContext,
        'No hay quincena abierta',
        fallbackContext: scaffoldContext,
        scope: 'NominaEmployeePayrollDialog',
      );
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
    var isSavingEntry = false;
    var isSendingPayroll = false;

    Future<void> reload(StateSetter setStateDialog) async {
      entries = await repo.listEntries(open.id, employee.id);
      totals = await repo.computeTotals(open.id, employee.id);
      setStateDialog(() {});
    }

    if (!context.mounted) return;

    try {
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
                      'Salario base: ${money.format(config?.baseSalary ?? employee.salarioBaseQuincenal)}',
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
                      initialValue: selectedType,
                      items: PayrollEntryType.values
                          .where(
                            (type) => type != PayrollEntryType.pagoCombustible,
                          )
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
                            'Ej: Ausencia 12/02, bonificación por meta, descuento administrativo...',
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
                      onPressed: isSavingEntry
                          ? null
                          : () async {
                              TraceLog.log(
                                'NominaEmployeePayrollDialog',
                                'add adjustment start dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                                seq: flowSeq,
                              );
                              final concept = conceptCtrl.text.trim();
                              if (concept.isEmpty) {
                                await AppFeedback.showError(
                                  scaffoldContext,
                                  'Debes escribir un concepto',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                                return;
                              }
                              final qty =
                                  double.tryParse(qtyCtrl.text.trim()) ?? 1;
                              if (qty <= 0) {
                                await AppFeedback.showError(
                                  scaffoldContext,
                                  'La cantidad debe ser > 0',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                                return;
                              }

                              final parsedAmount = double.tryParse(
                                amountCtrl.text.trim(),
                              );
                              double amount;

                              if (selectedType == PayrollEntryType.ausencia &&
                                  parsedAmount == null) {
                                final daily =
                                    (config?.baseSalary ??
                                        employee.salarioBaseQuincenal) /
                                    15;
                                amount = -(daily * qty);
                              } else {
                                if (parsedAmount == null) {
                                  await AppFeedback.showError(
                                    scaffoldContext,
                                    'Monto invalido',
                                    fallbackContext: context,
                                    scope: 'NominaEmployeePayrollDialog',
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

                              setStateDialog(() => isSavingEntry = true);

                              try {
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
                                TraceLog.log(
                                  'NominaEmployeePayrollDialog',
                                  'add adjustment saved dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                                  seq: flowSeq,
                                );
                                if (!context.mounted) return;
                                if (!scaffoldContext.mounted) return;
                                await AppFeedback.showInfo(
                                  scaffoldContext,
                                  'Ajuste guardado',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                              } catch (e, st) {
                                TraceLog.log(
                                  'NominaEmployeePayrollDialog',
                                  'add adjustment error',
                                  seq: flowSeq,
                                  error: e,
                                  stackTrace: st,
                                );
                                if (!context.mounted) return;
                                if (!scaffoldContext.mounted) return;
                                await AppFeedback.showError(
                                  scaffoldContext,
                                  'No se pudo guardar el ajuste: $e',
                                  fallbackContext: context,
                                  scope: 'NominaEmployeePayrollDialog',
                                );
                              } finally {
                                if (context.mounted) {
                                  setStateDialog(() => isSavingEntry = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.add),
                      label: isSavingEntry
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Agregar ajuste'),
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
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
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
              TextButton.icon(
                onPressed: isSendingPayroll
                    ? null
                    : () async {
                        setStateDialog(() => isSendingPayroll = true);
                        try {
                          await _sendPayrollToWhatsApp(
                            scaffoldContext,
                            ref,
                            period: open,
                            employee: employee,
                            totals: totals,
                          );
                        } catch (e, st) {
                          TraceLog.log(
                            'NominaEmployeePayrollDialog',
                            'send payroll whatsapp error',
                            seq: flowSeq,
                            error: e,
                            stackTrace: st,
                          );
                          if (!context.mounted) return;
                          if (!scaffoldContext.mounted) return;
                          await AppFeedback.showError(
                            scaffoldContext,
                            'No se pudo enviar la nómina: $e',
                            fallbackContext: context,
                            scope: 'NominaEmployeePayrollDialog',
                          );
                        } finally {
                          if (context.mounted) {
                            setStateDialog(() => isSendingPayroll = false);
                          }
                        }
                      },
                icon: isSendingPayroll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_to_mobile_outlined),
                label: const Text('Enviar nómina'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      conceptCtrl.dispose();
      amountCtrl.dispose();
      qtyCtrl.dispose();
    }

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

  Future<void> _showCreatePeriodDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final scaffoldContext = context;
    final flowSeq = TraceLog.nextSeq();
    var isSubmitting = false;
    final titleCtrl = TextEditingController();
    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(days: 14));

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !isSubmitting,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Nueva quincena'),
            content: AbsorbPointer(
              absorbing: isSubmitting,
              child: Column(
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
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        TraceLog.log(
                          'NominaCreatePeriodDialog',
                          'submit start dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                          seq: flowSeq,
                        );

                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) {
                          await AppFeedback.showError(
                            scaffoldContext,
                            'Debes indicar un titulo',
                            fallbackContext: context,
                            scope: 'NominaCreatePeriodDialog',
                          );
                          return;
                        }

                        setStateDialog(() => isSubmitting = true);

                        try {
                          await ref
                              .read(nominaHomeControllerProvider.notifier)
                              .createPeriod(
                                start: start,
                                end: end,
                                title: title,
                              );

                          TraceLog.log(
                            'NominaCreatePeriodDialog',
                            'submit success dialogMounted=${context.mounted} scaffoldMounted=${scaffoldContext.mounted}',
                            seq: flowSeq,
                          );

                          if (context.mounted) {
                            Navigator.pop(context);
                          }

                          if (!scaffoldContext.mounted) return;
                          await AppFeedback.showInfo(
                            scaffoldContext,
                            'Quincena creada correctamente',
                            fallbackContext: scaffoldContext,
                            scope: 'NominaCreatePeriodDialog',
                          );
                        } catch (e, st) {
                          TraceLog.log(
                            'NominaCreatePeriodDialog',
                            'submit error',
                            seq: flowSeq,
                            error: e,
                            stackTrace: st,
                          );

                          if (!context.mounted) return;
                          if (!scaffoldContext.mounted) return;
                          await AppFeedback.showError(
                            scaffoldContext,
                            'No se pudo crear: $e',
                            fallbackContext: context,
                            scope: 'NominaCreatePeriodDialog',
                          );
                        } finally {
                          TraceLog.log(
                            'NominaCreatePeriodDialog',
                            'submit finish dialogMounted=${context.mounted}',
                            seq: flowSeq,
                          );

                          if (context.mounted) {
                            setStateDialog(() => isSubmitting = false);
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear'),
              ),
            ],
          ),
        ),
      );
    } finally {
      titleCtrl.dispose();
    }
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

class _PayrollEmployeeDialog extends ConsumerStatefulWidget {
  const _PayrollEmployeeDialog({
    required this.employee,
    required this.selectedUser,
    required this.traceSeq,
  });

  final PayrollEmployee? employee;
  final UserModel? selectedUser;
  final int traceSeq;

  @override
  ConsumerState<_PayrollEmployeeDialog> createState() =>
      _PayrollEmployeeDialogState();
}

class _PayrollEmployeeDialogState
    extends ConsumerState<_PayrollEmployeeDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _roleCtrl;
  late final TextEditingController _salaryCtrl;
  late final TextEditingController _seguroLeyCtrl;
  late final TextEditingController _cuotaCtrl;

  bool _isSubmitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text:
          widget.employee?.nombre ?? widget.selectedUser?.nombreCompleto ?? '',
    );
    _phoneCtrl = TextEditingController(
      text: widget.employee?.telefono ?? widget.selectedUser?.telefono ?? '',
    );
    _roleCtrl = TextEditingController(
      text: widget.employee?.puesto ?? widget.selectedUser?.role ?? '',
    );
    _salaryCtrl = TextEditingController(
      text: widget.employee == null
          ? '0'
          : widget.employee!.salarioBaseQuincenal > 0
          ? widget.employee!.salarioBaseQuincenal.toStringAsFixed(2)
          : '',
    );
    _seguroLeyCtrl = TextEditingController(
      text: (widget.employee?.seguroLeyMonto ?? 0).toStringAsFixed(2),
    );
    _cuotaCtrl = TextEditingController(
      text: (widget.employee?.cuotaMinima ?? 0).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _roleCtrl.dispose();
    _salaryCtrl.dispose();
    _seguroLeyCtrl.dispose();
    _cuotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    TraceLog.log(
      'NominaEmployeeDialog',
      'submit start mounted=$mounted',
      seq: widget.traceSeq,
    );

    final salaryText = _salaryCtrl.text.trim();
    final salary = salaryText.isEmpty ? null : double.tryParse(salaryText);
    final cuota = double.tryParse(_cuotaCtrl.text.trim()) ?? -1;
    final seguroLey = double.tryParse(_seguroLeyCtrl.text.trim()) ?? -1;

    String? validationError;
    if (widget.employee == null && salary == null) {
      validationError = 'El salario base es obligatorio al agregar';
    } else if (salary != null && salary < 0) {
      validationError = 'El salario base debe ser un numero >= 0';
    } else if (cuota < 0) {
      validationError = 'La cuota minima debe ser un numero >= 0';
    } else if (seguroLey < 0) {
      validationError = 'El seguro de ley debe ser un monto >= 0';
    } else if (widget.employee == null && widget.selectedUser != null) {
      final alreadyExists = ref
          .read(nominaHomeControllerProvider)
          .employees
          .any((item) => item.id == widget.selectedUser!.id);
      if (alreadyExists) {
        validationError = 'Este usuario ya esta agregado en nomina';
      }
    }

    if (validationError != null) {
      if (!mounted) return;
      setState(() => _errorText = validationError);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await ref
          .read(nominaHomeControllerProvider.notifier)
          .saveEmployee(
            id: widget.employee?.id ?? widget.selectedUser?.id,
            nombre: _nameCtrl.text,
            telefono: _phoneCtrl.text,
            puesto: _roleCtrl.text,
            salarioBase: salary,
            cuotaMinima: cuota,
            seguroLeyMonto: seguroLey,
            activo: widget.employee?.activo ?? true,
          );

      TraceLog.log(
        'NominaEmployeeDialog',
        'submit save ok mounted=$mounted',
        seq: widget.traceSeq,
      );

      if (!mounted) return;
      Navigator.of(context).pop(
        widget.employee == null ? 'Empleado agregado' : 'Empleado actualizado',
      );
    } catch (e, st) {
      TraceLog.log(
        'NominaEmployeeDialog',
        'submit save error',
        seq: widget.traceSeq,
        error: e,
        stackTrace: st,
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorText = 'No se pudo guardar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Text(
          widget.employee == null ? 'Agregar empleado' : 'Editar empleado',
        ),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _nameCtrl,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _roleCtrl,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(labelText: 'Puesto'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _salaryCtrl,
                enabled: !_isSubmitting,
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
                controller: _cuotaCtrl,
                enabled: !_isSubmitting,
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
                controller: _seguroLeyCtrl,
                enabled: !_isSubmitting,
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
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _PayrollUserPickerDialog extends ConsumerStatefulWidget {
  const _PayrollUserPickerDialog({required this.excludedUserIds});

  final Set<String> excludedUserIds;

  @override
  ConsumerState<_PayrollUserPickerDialog> createState() =>
      _PayrollUserPickerDialogState();
}

class _PayrollUserPickerDialogState
    extends ConsumerState<_PayrollUserPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<UserModel> _users = const [];
  UserModel? _selected;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await ref.read(usersRepositoryProvider).fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'No se pudieron cargar usuarios: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final visible = _users.where((user) {
      if (widget.excludedUserIds.contains(user.id)) return false;
      if (query.isEmpty) return true;
      return user.nombreCompleto.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.telefono.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      title: const Text('Seleccionar usuario'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (_) {
                if (!mounted) return;
                setState(() {});
              },
              decoration: const InputDecoration(
                hintText: 'Buscar usuario...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(
              height: 300,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? const Center(child: Text('No hay usuarios para mostrar'))
                  : RadioGroup<String>(
                      groupValue: _selected?.id,
                      onChanged: (value) {
                        if (!mounted) return;
                        if (value == null) return;
                        UserModel? next;
                        for (final u in visible) {
                          if (u.id == value) {
                            next = u;
                            break;
                          }
                        }
                        if (next == null) return;
                        setState(() => _selected = next);
                      },
                      child: ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = visible[index];
                          return RadioListTile<String>(
                            value: user.id,
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
                          );
                        },
                      ),
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
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Seleccionar'),
        ),
      ],
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.onEdit,
    required this.onManage,
    required this.onDelete,
  });

  final PayrollEmployee employee;
  final VoidCallback onEdit;
  final VoidCallback onManage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                _compactInitials(employee.nombre),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${employee.puesto ?? 'Sin puesto'} · Base ${money.format(employee.salarioBaseQuincenal)} · Cuota ${money.format(employee.cuotaMinima)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CompactIconActionButton(
              tooltip: 'Movimientos',
              onPressed: onManage,
              icon: Icons.calculate_outlined,
              color: scheme.primary,
            ),
            _CompactIconActionButton(
              tooltip: 'Editar',
              onPressed: onEdit,
              icon: Icons.edit_outlined,
              color: scheme.primary,
            ),
            _CompactIconActionButton(
              tooltip: 'Eliminar',
              onPressed: onDelete,
              icon: Icons.delete_outline,
              color: scheme.error.withValues(alpha: 0.75),
            ),
          ],
        ),
      ),
    );
  }
}

class _NominaPremiumHeroCard extends StatelessWidget {
  const _NominaPremiumHeroCard({
    required this.title,
    required this.range,
    required this.totalLabel,
    required this.activeEmployees,
    required this.onHistory,
    required this.onTotals,
    required this.onPdf,
    required this.onAddEmployee,
    this.onCreatePeriod,
    this.onClosePeriod,
    this.compact = false,
  });

  final String title;
  final String range;
  final String totalLabel;
  final int activeEmployees;
  final VoidCallback? onHistory;
  final VoidCallback? onTotals;
  final VoidCallback? onPdf;
  final VoidCallback onAddEmployee;
  final VoidCallback? onCreatePeriod;
  final VoidCallback? onClosePeriod;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FDFF), Color(0xFFE4F3F7)],
        ),
        border: Border.all(color: const Color(0xFFB7D7E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12061523),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF0D3141),
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      range,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF4D6773),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _NominaTopBadge(icon: Icons.payments_outlined, label: totalLabel),
              const SizedBox(width: 8),
              _NominaTopBadge(
                icon: Icons.groups_2_outlined,
                label: '$activeEmployees',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _NominaHeroActionButton(
                label: 'Agregar usuario',
                icon: Icons.person_add_alt_1_outlined,
                onPressed: onAddEmployee,
                solid: true,
                iconOnly: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _NominaHeroActionButton(
                        label: 'Historial',
                        icon: Icons.history,
                        onPressed: onHistory,
                      ),
                      _NominaHeroActionButton(
                        label: 'Totales',
                        icon: Icons.summarize_outlined,
                        onPressed: onTotals,
                      ),
                      _NominaHeroActionButton(
                        label: 'PDF',
                        icon: Icons.picture_as_pdf_outlined,
                        onPressed: onPdf,
                      ),
                      if (onClosePeriod != null)
                        _NominaHeroActionButton(
                          label: 'Cerrar',
                          icon: Icons.task_alt_outlined,
                          onPressed: onClosePeriod,
                        ),
                      if (onCreatePeriod != null)
                        _NominaHeroActionButton(
                          label: 'Abrir',
                          icon: Icons.add_circle_outline,
                          onPressed: onCreatePeriod,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NominaTopBadge extends StatelessWidget {
  const _NominaTopBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD3E5EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF0E708E)),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: const Color(0xFF123747),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _NominaHeroActionButton extends StatelessWidget {
  const _NominaHeroActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.solid = false,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool solid;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final basePadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9);
    final style = solid
        ? FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F6F8B),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: basePadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF164354),
            side: const BorderSide(color: Color(0xFFC7DDE5)),
            padding: basePadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );

    final child = iconOnly
        ? Tooltip(
            message: label,
            child: solid
                ? FilledButton(
                    onPressed: onPressed,
                    style: style,
                    child: Icon(icon, size: 18),
                  )
                : OutlinedButton(
                    onPressed: onPressed,
                    style: style,
                    child: Icon(icon, size: 18),
                  ),
          )
        : solid
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: style,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: style,
          );

    return Padding(padding: const EdgeInsets.only(right: 8), child: child);
  }
}

class _NominaPrimaryBoard extends StatelessWidget {
  const _NominaPrimaryBoard({
    required this.openPeriod,
    required this.totalAbierto,
    required this.payrollBase,
    required this.payrollQuota,
    required this.activeEmployees,
    required this.money,
    this.compact = false,
  });

  final PayrollPeriod? openPeriod;
  final double totalAbierto;
  final double payrollBase;
  final double payrollQuota;
  final int activeEmployees;
  final NumberFormat money;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.68),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10061523),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detalle de la quincena en curso',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      openPeriod == null
                          ? 'Sin periodo abierto'
                          : openPeriod!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: openPeriod == null
                      ? scheme.surfaceContainerHigh
                      : scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  openPeriod == null ? 'Sin apertura' : 'Abierta',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: openPeriod == null
                        ? scheme.onSurfaceVariant
                        : scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _NominaMiniStatTile(
                label: 'Total',
                value: money.format(totalAbierto),
                icon: Icons.account_balance_wallet_outlined,
              ),
              _NominaMiniStatTile(
                label: 'Base',
                value: money.format(payrollBase),
                icon: Icons.badge_outlined,
              ),
              _NominaMiniStatTile(
                label: 'Cuota',
                value: money.format(payrollQuota),
                icon: Icons.flag_outlined,
              ),
              _NominaMiniStatTile(
                label: 'Activos',
                value: activeEmployees.toString(),
                icon: Icons.groups_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NominaMiniStatTile extends StatelessWidget {
  const _NominaMiniStatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 164, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
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

class _NominaUsersSectionCard extends StatelessWidget {
  const _NominaUsersSectionCard({
    required this.expanded,
    required this.employees,
    required this.onToggle,
    required this.onAdd,
    required this.child,
  });

  final bool expanded;
  final List<PayrollEmployee> employees;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.68),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10061523),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usuarios en nomina',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${employees.length} registrados',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _CompactIconActionButton(
                tooltip: expanded ? 'Ocultar' : 'Mostrar',
                onPressed: onToggle,
                icon: expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: scheme.primary,
              ),
              _CompactIconActionButton(
                tooltip: 'Agregar usuario',
                onPressed: onAdd,
                icon: Icons.person_add_alt_1_outlined,
                color: scheme.primary,
              ),
            ],
          ),
          if (expanded) ...[const SizedBox(height: 10), child],
        ],
      ),
    );
  }
}

class _NominaErrorBanner extends StatelessWidget {
  const _NominaErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.error.withValues(alpha: 0.18)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PayrollHistoryPeriodSummary {
  const _PayrollHistoryPeriodSummary({
    required this.period,
    required this.total,
  });

  final PayrollPeriod period;
  final double total;
}

enum _PayrollHistoryQuickFilter {
  all('Todo'),
  last90Days('90 dias'),
  currentYear('Este ano');

  const _PayrollHistoryQuickFilter(this.label);
  final String label;
}

enum _PayrollDetailEmployeeFilter {
  all('Todos'),
  withCommission('Con comision'),
  withDeductions('Con deducciones');

  const _PayrollDetailEmployeeFilter(this.label);
  final String label;
}

class _PayrollHistoryFullScreen extends StatefulWidget {
  const _PayrollHistoryFullScreen({
    required this.items,
    required this.onOpenDetails,
  });

  final List<_PayrollHistoryPeriodSummary> items;
  final Future<void> Function(PayrollPeriod period) onOpenDetails;

  @override
  State<_PayrollHistoryFullScreen> createState() =>
      _PayrollHistoryFullScreenState();
}

class _PayrollHistoryFullScreenState extends State<_PayrollHistoryFullScreen> {
  late final TextEditingController _searchController;
  DateTime? _from;
  DateTime? _to;
  _PayrollHistoryQuickFilter _quickFilter = _PayrollHistoryQuickFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom
        ? (_from ?? now.subtract(const Duration(days: 180)))
        : (_to ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) {
          _to = picked;
        }
      } else {
        _to = picked;
        if (_from != null && picked.isBefore(_from!)) {
          _from = picked;
        }
      }
    });
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _from = null;
      _to = null;
      _quickFilter = _PayrollHistoryQuickFilter.all;
    });
  }

  List<_PayrollHistoryPeriodSummary> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    final now = DateTime.now();
    return widget.items
        .where((item) {
          if (query.isNotEmpty &&
              !item.period.title.toLowerCase().contains(query)) {
            return false;
          }

          if (_quickFilter == _PayrollHistoryQuickFilter.last90Days) {
            final pivot = now.subtract(const Duration(days: 90));
            if (item.period.endDate.isBefore(pivot)) return false;
          }

          if (_quickFilter == _PayrollHistoryQuickFilter.currentYear &&
              item.period.endDate.year != now.year) {
            return false;
          }

          if (_from != null) {
            final from = DateTime(_from!.year, _from!.month, _from!.day);
            if (item.period.endDate.isBefore(from)) return false;
          }

          if (_to != null) {
            final to = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59);
            if (item.period.startDate.isAfter(to)) return false;
          }

          return true;
        })
        .toList(growable: false)
      ..sort((a, b) => b.period.endDate.compareTo(a.period.endDate));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtered = _filteredItems;
    final activeFilters = [
      if (_searchController.text.trim().isNotEmpty) 1,
      if (_from != null) 1,
      if (_to != null) 1,
      if (_quickFilter != _PayrollHistoryQuickFilter.all) 1,
    ].length;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final visibleTotal = filtered.fold<double>(
      0,
      (sum, item) => sum + item.total,
    );
    final latestClose = filtered.isEmpty
        ? null
        : DateFormat('dd/MM/yyyy').format(filtered.first.period.endDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de nominas'),
        actions: [
          if (activeFilters > 0)
            TextButton(onPressed: _resetFilters, child: const Text('Limpiar')),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _PayrollSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quincenas cerradas',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              filtered.isEmpty
                                  ? 'No hay quincenas visibles con los filtros actuales.'
                                  : '${filtered.length} resultados visibles.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (activeFilters > 0)
                        TextButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Limpiar'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 12,
                    children: [
                      _PayrollHeaderMetric(
                        icon: Icons.receipt_long_outlined,
                        label: 'Quincenas',
                        value: '${filtered.length}',
                      ),
                      _PayrollHeaderMetric(
                        icon: Icons.payments_outlined,
                        label: 'Total visible',
                        value: money.format(visibleTotal),
                      ),
                      _PayrollHeaderMetric(
                        icon: Icons.event_available_outlined,
                        label: 'Ultimo cierre',
                        value: latestClose ?? 'Sin datos',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por titulo de quincena',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      fillColor: scheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _PayrollHistoryQuickFilter.values
                          .map(
                            (filter) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _PayrollFilterChip(
                                label: filter.label,
                                selected: _quickFilter == filter,
                                onTap: () =>
                                    setState(() => _quickFilter = filter),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PayrollFilterButton(
                          label: 'Desde',
                          value: _from == null
                              ? 'Seleccionar fecha'
                              : DateFormat('dd/MM/yyyy').format(_from!),
                          icon: Icons.calendar_today_outlined,
                          onTap: () => _pickDate(isFrom: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PayrollFilterButton(
                          label: 'Hasta',
                          value: _to == null
                              ? 'Seleccionar fecha'
                              : DateFormat('dd/MM/yyyy').format(_to!),
                          icon: Icons.event_available_outlined,
                          onTap: () => _pickDate(isFrom: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _NominaEmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No hay quincenas con estos filtros',
                        message:
                            'Ajusta la busqueda o el rango de fechas para ver resultados.',
                        actionLabel: 'Limpiar filtros',
                        onAction: _resetFilters,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _PayrollHistoryPeriodCard(
                        item: item,
                        onTap: () => widget.onOpenDetails(item.period),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PayrollPeriodDetailsScreen extends StatefulWidget {
  const _PayrollPeriodDetailsScreen({
    required this.period,
    required this.rows,
    required this.totalPagar,
    required this.onOpenPdf,
    required this.onSendPayroll,
    required this.money,
  });

  final PayrollPeriod period;
  final List<_PayrollPeriodRow> rows;
  final double totalPagar;
  final Future<void> Function() onOpenPdf;
  final Future<void> Function(_PayrollPeriodRow row) onSendPayroll;
  final NumberFormat money;

  @override
  State<_PayrollPeriodDetailsScreen> createState() =>
      _PayrollPeriodDetailsScreenState();
}

class _PayrollPeriodDetailsScreenState
    extends State<_PayrollPeriodDetailsScreen> {
  late final TextEditingController _searchController;
  _PayrollDetailEmployeeFilter _filter = _PayrollDetailEmployeeFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_PayrollPeriodRow> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();
    return widget.rows
        .where((row) {
          if (query.isNotEmpty &&
              !row.employee.nombre.toLowerCase().contains(query)) {
            return false;
          }
          switch (_filter) {
            case _PayrollDetailEmployeeFilter.withCommission:
              return row.totals.commissions > 0;
            case _PayrollDetailEmployeeFilter.withDeductions:
              return row.totals.deductions > 0;
            case _PayrollDetailEmployeeFilter.all:
              return true;
          }
        })
        .toList(growable: false)
      ..sort((a, b) => b.totals.total.compareTo(a.totals.total));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 420;
    final filtered = _filteredRows;
    final activeFilters = [
      if (_searchController.text.trim().isNotEmpty) 1,
      if (_filter != _PayrollDetailEmployeeFilter.all) 1,
    ].length;
    final totalBase = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.baseSalary,
    );
    final totalCommissions = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.commissions,
    );
    final totalDeductions = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.deductions,
    );
    final totalExtras = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.bonuses + row.totals.otherAdditions,
    );
    final totalVisible = filtered.fold<double>(
      0,
      (sum, row) => sum + row.totals.total,
    );
    final range =
        '${DateFormat('dd/MM/yyyy').format(widget.period.startDate)} - ${DateFormat('dd/MM/yyyy').format(widget.period.endDate)}';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 0,
        title: Text(
          widget.period.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            onPressed: () => widget.onOpenPdf(),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(12, isCompact ? 10 : 12, 12, 0),
            child: _PayrollSurface(
              padding: EdgeInsets.all(isCompact ? 10 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detalle premium de quincena',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              range,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.money.format(widget.totalPagar),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Total general de la quincena',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _PayrollMiniPill(
                        icon: Icons.groups_outlined,
                        label: '${filtered.length} empleados',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _PayrollInlineMetric(
                          label: 'Base',
                          value: widget.money.format(totalBase),
                        ),
                        _PayrollInlineMetric(
                          label: 'Comision',
                          value: widget.money.format(totalCommissions),
                        ),
                        _PayrollInlineMetric(
                          label: 'Extras',
                          value: widget.money.format(totalExtras),
                        ),
                        _PayrollInlineMetric(
                          label: 'Deducciones',
                          value: widget.money.format(totalDeductions),
                        ),
                        _PayrollInlineMetric(
                          label: 'Neto visible',
                          value: widget.money.format(totalVisible),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: isCompact ? 10 : 12,
                    ),
                    child: Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Filtros del detalle',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (activeFilters > 0)
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _filter = _PayrollDetailEmployeeFilter.all;
                          }),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Mostrar todo'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre del empleado',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: scheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _PayrollDetailEmployeeFilter.values
                          .map(
                            (filter) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _PayrollFilterChip(
                                label: filter.label,
                                selected: _filter == filter,
                                onTap: () => setState(() => _filter = filter),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _NominaEmptyState(
                        icon: Icons.people_outline,
                        title: 'No hay empleados con este filtro',
                        message:
                            'Prueba con otro criterio para ver el detalle de la quincena.',
                        actionLabel: 'Mostrar todo',
                        onAction: () => setState(() {
                          _searchController.clear();
                          _filter = _PayrollDetailEmployeeFilter.all;
                        }),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(12, isCompact ? 6 : 8, 12, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = filtered[index];
                      return _PayrollPeriodEmployeeCard(
                        row: row,
                        money: widget.money,
                        onSendPayroll: () => widget.onSendPayroll(row),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PayrollSurface extends StatelessWidget {
  const _PayrollSurface({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surface, scheme.surfaceContainerLowest],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PayrollMiniPill extends StatelessWidget {
  const _PayrollMiniPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.primary.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollInlineMetric extends StatelessWidget {
  const _PayrollInlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollHeaderMetric extends StatelessWidget {
  const _PayrollHeaderMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayrollAmountBadge extends StatelessWidget {
  const _PayrollAmountBadge({
    required this.label,
    required this.value,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
  });

  final String label;
  final String value;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = backgroundColor ?? scheme.surfaceContainerLowest;
    final fg = textColor ?? scheme.onSurface;
    final bd = borderColor ?? scheme.outlineVariant.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: fg,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayrollFilterChip extends StatelessWidget {
  const _PayrollFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    scheme.primary,
                    scheme.primary.withValues(alpha: 0.82),
                  ],
                )
              : null,
          color: selected ? null : scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PayrollFilterButton extends StatelessWidget {
  const _PayrollFilterButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _PayrollHistoryPeriodCard extends StatelessWidget {
  const _PayrollHistoryPeriodCard({required this.item, required this.onTap});

  final _PayrollHistoryPeriodSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final range =
        '${DateFormat('dd/MM/yyyy').format(item.period.startDate)} - ${DateFormat('dd/MM/yyyy').format(item.period.endDate)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    _compactInitials(item.period.title),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.period.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        range,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PayrollAmountBadge(
                            label: 'Total pagado',
                            value: money.format(item.total),
                            backgroundColor: scheme.primaryContainer,
                            textColor: scheme.onPrimaryContainer,
                            borderColor: scheme.primary.withValues(alpha: 0.18),
                          ),
                          _PayrollAmountBadge(
                            label: 'Estado',
                            value: 'Cerrada',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayrollPeriodEmployeeCard extends StatelessWidget {
  const _PayrollPeriodEmployeeCard({
    required this.row,
    required this.money,
    required this.onSendPayroll,
  });

  final _PayrollPeriodRow row;
  final NumberFormat money;
  final Future<void> Function() onSendPayroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 420;
    final extras = row.totals.bonuses + row.totals.otherAdditions;
    final breakdownParts = <String>[
      'Base ${money.format(row.totals.baseSalary)}',
      'Comision ${money.format(row.totals.commissions)}',
      if (extras > 0) 'Extras ${money.format(extras)}',
      'Deducciones ${money.format(row.totals.deductions)}',
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surface, scheme.surfaceContainerLowest],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 12,
          vertical: isCompact ? 9 : 11,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: isCompact ? 42 : 46,
                  decoration: BoxDecoration(
                    color: row.totals.total < 0
                        ? scheme.error
                        : scheme.primary.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: isCompact ? 17 : 18,
                  backgroundColor: scheme.secondaryContainer,
                  child: Text(
                    _compactInitials(row.employee.nombre),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.employee.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        breakdownParts.join(' · '),
                        maxLines: isCompact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: row.totals.total < 0
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: row.totals.total < 0
                          ? scheme.error.withValues(alpha: 0.18)
                          : scheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        money.format(row.totals.total),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: row.totals.total < 0
                              ? scheme.onErrorContainer
                              : scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        'Neto',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: row.totals.total < 0
                              ? scheme.onErrorContainer.withValues(alpha: 0.78)
                              : scheme.onPrimaryContainer.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onSendPayroll,
                icon: const Icon(Icons.send_to_mobile_outlined, size: 18),
                label: const Text('Enviar nómina'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactIconActionButton extends StatelessWidget {
  const _CompactIconActionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        icon: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

String _compactInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList(growable: false);
  if (parts.isEmpty) return '--';
  return parts.map((part) => part[0].toUpperCase()).join();
}

class _NominaEmptyState extends StatelessWidget {
  const _NominaEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
