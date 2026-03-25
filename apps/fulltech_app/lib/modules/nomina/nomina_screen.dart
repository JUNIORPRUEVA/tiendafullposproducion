import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
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

class NominaScreen extends ConsumerStatefulWidget {
  const NominaScreen({super.key});

  @override
  ConsumerState<NominaScreen> createState() => _NominaScreenState();
}

class _NominaScreenState extends ConsumerState<NominaScreen> {
  String? _selectedDesktopEmployeeId;

  PayrollEmployee? _selectedDesktopEmployee(List<PayrollEmployee> employees) {
    if (employees.isEmpty) {
      _selectedDesktopEmployeeId = null;
      return null;
    }

    for (final employee in employees) {
      if (employee.id == _selectedDesktopEmployeeId) {
        return employee;
      }
    }

    final fallback = employees.first;
    _selectedDesktopEmployeeId = fallback.id;
    return fallback;
  }

  Widget _buildDesktopAdminBody(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');
    final openPeriod = state.openPeriod;
    final closedPeriods = state.periods
        .where((period) => !period.isOpen)
        .length;
    final activeEmployees = state.employees
        .where((employee) => employee.activo)
        .length;
    final payrollBase = state.employees.fold<double>(
      0,
      (sum, employee) => sum + employee.salarioBaseQuincenal,
    );
    final payrollQuota = state.employees.fold<double>(
      0,
      (sum, employee) => sum + employee.cuotaMinima,
    );
    final selectedEmployee = _selectedDesktopEmployee(state.employees);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.primary.withValues(alpha: 0.03),
            scheme.surface,
          ],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: ref.read(nominaHomeControllerProvider.notifier).load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0F3D91), Color(0xFF081A33)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _NominaDesktopMetric(
                                label: 'Quincena activa',
                                value: openPeriod?.title ?? 'Sin apertura',
                                icon: Icons.event_note_outlined,
                                accent: const Color(0xFF93C5FD),
                                dark: true,
                              ),
                              _NominaDesktopMetric(
                                label: 'Empleados activos',
                                value: activeEmployees.toString(),
                                icon: Icons.groups_2_outlined,
                                accent: const Color(0xFFFDE68A),
                                dark: true,
                              ),
                              _NominaDesktopMetric(
                                label: 'Total abierto',
                                value: money.format(state.openPeriodTotal ?? 0),
                                icon: Icons.account_balance_wallet_outlined,
                                accent: const Color(0xFF86EFAC),
                                dark: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 250,
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _showCreatePeriodDialog(context, ref),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Nueva quincena'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF0F172A),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: state.loading
                                      ? null
                                      : () => _openOpenPeriodTotalsDialog(
                                          context,
                                          ref,
                                          state,
                                        ),
                                  icon: const Icon(Icons.summarize_outlined),
                                  label: const Text('Ver totales'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: state.loading
                                      ? null
                                      : () => _openPayrollHistoryDialog(
                                          context,
                                          ref,
                                          state,
                                        ),
                                  icon: const Icon(Icons.history),
                                  label: const Text('Historial'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 340,
                        child: Column(
                          children: [
                            _NominaDesktopPanel(
                              title: 'Resumen ejecutivo',
                              subtitle: 'Indicadores clave del ciclo actual',
                              child: Column(
                                children: [
                                  _NominaInfoLine(
                                    label: 'Quincenas registradas',
                                    value: state.periods.length.toString(),
                                  ),
                                  _NominaInfoLine(
                                    label: 'Quincenas cerradas',
                                    value: closedPeriods.toString(),
                                  ),
                                  _NominaInfoLine(
                                    label: 'Base quincenal equipo',
                                    value: money.format(payrollBase),
                                  ),
                                  _NominaInfoLine(
                                    label: 'Cuotas acumuladas',
                                    value: money.format(payrollQuota),
                                  ),
                                  _NominaInfoLine(
                                    label: 'Estado operativo',
                                    value: openPeriod != null
                                        ? 'Activa'
                                        : 'Pendiente',
                                    emphasized: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _NominaDesktopPanel(
                              title: 'Control operativo',
                              subtitle: 'Acciones administrativas prioritarias',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Combustible y pagos asociados ya aprobados se consolidan aquí para completar la nómina sin duplicar revisión operativa.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      height: 1.45,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.tonalIcon(
                                      onPressed: () =>
                                          context.go(Routes.administracion),
                                      icon: const Icon(
                                        Icons.admin_panel_settings_outlined,
                                      ),
                                      label: const Text('Abrir administración'),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: state.loading
                                          ? null
                                          : () => _importOpenPeriodFuelPayments(
                                              context,
                                              ref,
                                              state,
                                            ),
                                      icon: const Icon(
                                        Icons.local_gas_station_outlined,
                                      ),
                                      label: const Text('Importar combustible'),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: state.loading
                                          ? null
                                          : () => _exportOpenPeriodPdf(
                                              context,
                                              ref,
                                              state,
                                            ),
                                      icon: const Icon(
                                        Icons.picture_as_pdf_outlined,
                                      ),
                                      label: const Text('Exportar PDF'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (state.error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: scheme.errorContainer,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: scheme.error.withValues(alpha: 0.24),
                                  ),
                                ),
                                child: Text(
                                  state.error!,
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _NominaSummaryCard(state: state),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _NominaDesktopPanel(
                                    title: 'Quincena actual',
                                    subtitle: openPeriod != null
                                        ? '${DateFormat('dd/MM/yyyy').format(openPeriod.startDate)} - ${DateFormat('dd/MM/yyyy').format(openPeriod.endDate)}'
                                        : 'No hay una quincena abierta en este momento',
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          openPeriod != null
                                              ? 'El tablero está listo para seguimiento, cálculo de totales y cierre cuando el ciclo operativo termine.'
                                              : 'Crea una quincena para habilitar importaciones, consolidación de pagos y cierre administrativo.',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                                height: 1.45,
                                              ),
                                        ),
                                        const SizedBox(height: 14),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: [
                                            _NominaDesktopMetric(
                                              label: 'Total abierto',
                                              value: money.format(
                                                state.openPeriodTotal ?? 0,
                                              ),
                                              icon: Icons.payments_outlined,
                                              accent: scheme.primary,
                                            ),
                                            _NominaDesktopMetric(
                                              label: 'Activos en nómina',
                                              value: activeEmployees.toString(),
                                              icon: Icons.badge_outlined,
                                              accent: scheme.secondary,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _NominaDesktopPanel(
                              title: 'Quincenas',
                              subtitle:
                                  'Seguimiento de ciclos abiertos y cerrados',
                              action: TextButton.icon(
                                onPressed: () =>
                                    _showCreatePeriodDialog(context, ref),
                                icon: const Icon(Icons.add),
                                label: const Text('Crear'),
                              ),
                              child: state.periods.isEmpty
                                  ? _NominaEmptyState(
                                      icon: Icons.event_note_outlined,
                                      title: 'Aún no hay quincenas creadas',
                                      message:
                                          'Crea la primera quincena para comenzar la gestión de nómina.',
                                      actionLabel: 'Crear quincena',
                                      onAction: () =>
                                          _showCreatePeriodDialog(context, ref),
                                    )
                                  : Column(
                                      children: state.periods
                                          .map(
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
                                          )
                                          .toList(growable: false),
                                    ),
                            ),
                            const SizedBox(height: 16),
                            _NominaDesktopPanel(
                              title: 'Equipo de ventas',
                              subtitle:
                                  'Selección directa del personal, cuotas y salario base',
                              action: FilledButton.tonalIcon(
                                onPressed: () =>
                                    _showEmployeeDialog(context, ref),
                                icon: const Icon(Icons.add),
                                label: const Text('Agregar empleado'),
                              ),
                              child: state.employees.isEmpty
                                  ? _NominaEmptyState(
                                      icon: Icons.groups_outlined,
                                      title:
                                          'No hay empleados de nómina registrados',
                                      message:
                                          'Agrega vendedores o personal de nómina para administrar su configuración y movimientos.',
                                      actionLabel: 'Agregar empleado',
                                      onAction: () =>
                                          _showEmployeeDialog(context, ref),
                                    )
                                  : selectedEmployee == null
                                  ? const SizedBox.shrink()
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Row(
                                            children: state.employees
                                                .map(
                                                  (
                                                    employee,
                                                  ) => _NominaDesktopEmployeeSelector(
                                                    employee: employee,
                                                    selected:
                                                        employee.id ==
                                                        selectedEmployee.id,
                                                    onTap: () => setState(
                                                      () =>
                                                          _selectedDesktopEmployeeId =
                                                              employee.id,
                                                    ),
                                                  ),
                                                )
                                                .toList(growable: false),
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        _NominaDesktopEmployeeRow(
                                          employee: selectedEmployee,
                                          selected: true,
                                          onTap: () {},
                                          onManage: () =>
                                              _showEmployeePayrollDialog(
                                                context,
                                                ref,
                                                selectedEmployee,
                                              ),
                                          onEdit: () => _showEmployeeDialog(
                                            context,
                                            ref,
                                            employee: selectedEmployee,
                                          ),
                                          onDelete: () =>
                                              _confirmDeleteEmployee(
                                                context,
                                                ref,
                                                selectedEmployee,
                                              ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
              tooltip: 'Importar combustible',
              onPressed: state.loading
                  ? null
                  : () => _importOpenPeriodFuelPayments(context, ref, state),
              icon: const Icon(Icons.local_gas_station_outlined),
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
        drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
        floatingActionButton: isDesktop
            ? null
            : Column(
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
                        : () =>
                              _openOpenPeriodTotalsDialog(context, ref, state),
                    icon: const Icon(Icons.summarize_outlined),
                    label: const Text('Totales'),
                  ),
                ],
              ),
        body: isDesktop
            ? _buildDesktopAdminBody(context, ref, state)
            : RefreshIndicator(
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
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.local_gas_station_outlined,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Combustible técnico y nómina',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'La revisión operativa de salidas, aprobación y pagos de combustible se administra visualmente desde Administración > Combustible. Desde Nómina solo se importan los pagos ya marcados como pagados.',
                                      ),
                                      const SizedBox(height: 14),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: [
                                          FilledButton.icon(
                                            onPressed: () => context.go(
                                              Routes.administracion,
                                            ),
                                            icon: const Icon(
                                              Icons
                                                  .admin_panel_settings_outlined,
                                            ),
                                            label: const Text(
                                              'Abrir administración',
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: state.loading
                                                ? null
                                                : () =>
                                                      _importOpenPeriodFuelPayments(
                                                        context,
                                                        ref,
                                                        state,
                                                      ),
                                            icon: const Icon(
                                              Icons.payments_outlined,
                                            ),
                                            label: const Text(
                                              'Importar a nómina',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (state.error != null)
                                Card(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.errorContainer,
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
                                              _showCreatePeriodDialog(
                                                context,
                                                ref,
                                              ),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
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
                                      side: const BorderSide(
                                        color: Colors.white70,
                                      ),
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
                                    onDelete: () => _confirmDeleteEmployee(
                                      context,
                                      ref,
                                      employee,
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

  Future<void> _importOpenPeriodFuelPayments(
    BuildContext context,
    WidgetRef ref,
    NominaHomeState state,
  ) async {
    final open = state.openPeriod;
    if (open == null) {
      AppFeedback.showError(
        context,
        'No hay una quincena abierta para importar combustible.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar combustible'),
        content: Text(
          'Se importarán a la quincena abierta los pagos de combustible ya pagados y aún no vinculados a nómina.\n\n'
          'Quincena: ${open.title}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref
          .read(nominaRepositoryProvider)
          .importFuelPayments(periodId: open.id);
      await ref.read(nominaHomeControllerProvider.notifier).load();
      if (!context.mounted) return;

      final importedCount = (result['importedCount'] as num?)?.toInt() ?? 0;
      final skippedCount = (result['skippedCount'] as num?)?.toInt() ?? 0;
      AppFeedback.showInfo(
        context,
        importedCount > 0
            ? 'Combustible importado: $importedCount movimiento(s).'
            : skippedCount > 0
            ? 'No hubo movimientos nuevos; se omitieron $skippedCount registro(s).'
            : 'No había pagos de combustible pendientes para esta quincena.',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.showError(context, 'No se pudo importar combustible: $e');
    }
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
    required this.onDelete,
  });

  final PayrollEmployee employee;
  final VoidCallback onEdit;
  final VoidCallback onManage;
  final VoidCallback onDelete;

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
          'Salario base: ${money.format(employee.salarioBaseQuincenal)}\n'
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
            IconButton(
              tooltip: 'Eliminar',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _NominaDesktopPanel extends StatelessWidget {
  const _NominaDesktopPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 16), action!],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _NominaDesktopMetric extends StatelessWidget {
  const _NominaDesktopMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.dark = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = dark ? Colors.white : theme.colorScheme.onSurface;
    final muted = dark
        ? Colors.white.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.12)
              : accent.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: dark ? Colors.white : accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NominaInfoLine extends StatelessWidget {
  const _NominaInfoLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
              color: emphasized ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
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

class _NominaDesktopEmployeeSelector extends StatelessWidget {
  const _NominaDesktopEmployeeSelector({
    required this.employee,
    required this.selected,
    required this.onTap,
  });

  final PayrollEmployee employee;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: employee.activo
                      ? const Color(0xFF16A34A)
                      : scheme.outline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  employee.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NominaDesktopEmployeeRow extends StatelessWidget {
  const _NominaDesktopEmployeeRow({
    required this.employee,
    required this.onTap,
    required this.onEdit,
    required this.onManage,
    required this.onDelete,
    this.selected = false,
  });

  final PayrollEmployee employee;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onManage;
  final VoidCallback onDelete;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final money = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.55)
                  : scheme.outlineVariant.withValues(alpha: 0.75),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  employee.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Text(
                  employee.puesto ?? 'Sin puesto',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: Text(
                  money.format(employee.salarioBaseQuincenal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: Text(
                  money.format(employee.cuotaMinima),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                child: Text(
                  money.format(employee.seguroLeyMonto),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: employee.activo
                      ? const Color(0xFFDCFCE7)
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  employee.activo ? 'Activo' : 'Inactivo',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: employee.activo
                        ? const Color(0xFF166534)
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
              IconButton(
                tooltip: 'Eliminar',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
